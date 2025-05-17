use audiotags::Tag;
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use rayon::{ThreadPool, ThreadPoolBuilder};
use regex::Regex;
use rodio::{Decoder, OutputStream, OutputStreamHandle, Sink, Source};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::cmp::max;
use std::collections::HashMap;
use std::fs;
use std::io::{BufReader, Cursor, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{
    mpsc::{self, Receiver, Sender},
    Arc, Mutex, RwLock,
};
use std::thread;
use std::time::{Duration, Instant};
use walkdir::WalkDir;

fn get_mp3_cache_dir() -> PathBuf {
    let mut cache_dir = std::env::temp_dir();
    cache_dir.push("adiman_mp3_cache");
    if !cache_dir.exists() {
        let _ = fs::create_dir_all(&cache_dir);
    }
    cache_dir
}

// Given an original file path, compute the cached mp3 file path.
// We use a hash of the absolute path to produce a unique file name.
fn get_cached_mp3_path(original: &Path) -> PathBuf {
    let mut hasher = Sha256::new();
    hasher.update(original.to_string_lossy().as_bytes());
    let hash = format!("{:x}", hasher.finalize());
    let mut cache_path = get_mp3_cache_dir();
    cache_path.push(format!("{}.mp3", hash));
    cache_path
}

#[derive(Clone)]
struct StreamingBuffer {
    chunks: Arc<Mutex<Vec<AudioChunk>>>,
    sample_rate: u32,
    channels: u16,
    total_duration: Duration,
}

#[derive(Clone)]
struct AudioChunk {
    samples: Vec<f32>,
}

enum PlayerMessage {
    Load { path: String, position: f32 },
    Seek(f32),
    Stop,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SongMetadata {
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: u64,
    pub path: String,
    pub album_art: Option<String>,
    pub genre: String,
}

#[derive(Debug, Default)]
pub struct PlayerState {
    pub initialized: bool,
}

struct StreamWrapper(OutputStream);
unsafe impl Send for StreamWrapper {}
unsafe impl Sync for StreamWrapper {}

static STREAM: Lazy<Mutex<Option<StreamWrapper>>> = Lazy::new(|| Mutex::new(None));
static PLAYER: Lazy<Mutex<Option<AudioPlayer>>> = Lazy::new(|| Mutex::new(None));
static PLAYER_STATE: Lazy<Mutex<PlayerState>> = Lazy::new(|| Mutex::new(PlayerState::default()));

struct AudioPlayer {
    sink: Mutex<Option<Arc<Sink>>>,
    current_file: Mutex<String>,
    start_time: Mutex<Instant>,
    playing: Mutex<bool>,
    album_art_cache: Mutex<HashMap<String, String>>,
    sender: Mutex<Sender<PlayerMessage>>,
    buffer: Arc<Mutex<Option<StreamingBuffer>>>,
    paused_position: Mutex<f32>,
    is_paused: Mutex<bool>,
}

impl std::fmt::Debug for AudioPlayer {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AudioPlayer")
            .field("sink", &"<SinkMutex>")
            .finish()
    }
}

impl AudioPlayer {
    fn new() -> Option<Self> {
        if let Ok((stream, handle)) = OutputStream::try_default() {
            // Create a channel for commands
            let (tx, rx) = mpsc::channel();
            let buffer = Arc::new(Mutex::new(None));
            let buffer_clone = Arc::clone(&buffer);
            let handle_clone = handle.clone();
            // Spawn the background worker with a cloned stream handle and buffer.
            thread::spawn(move || Self::background_worker(rx, handle_clone, buffer_clone));
            if let Ok(mut stream_guard) = STREAM.lock() {
                *stream_guard = Some(StreamWrapper(stream));
                return Some(Self {
                    sink: Mutex::new(None),
                    current_file: Mutex::new(String::new()),
                    start_time: Mutex::new(Instant::now()),
                    playing: Mutex::new(false),
                    album_art_cache: Mutex::new(HashMap::new()),
                    sender: Mutex::new(tx),
                    buffer,
                    paused_position: Mutex::new(0.0),
                    is_paused: Mutex::new(false),
                });
            }
        }
        None
    }

    fn pause(&self) -> bool {
        if let Some(sink) = self.sink.lock().unwrap().as_ref() {
            sink.pause();
            {
                let mut playing = self.playing.lock().unwrap();
                *playing = false;
            }
            let pos = self.get_position();
            {
                let mut paused_pos = self.paused_position.lock().unwrap();
                *paused_pos = pos;
            }
            *self.is_paused.lock().unwrap() = true;
            return true;
        }
        false
    }

    fn resume(&self) -> bool {
        if let Some(sink) = self.sink.lock().unwrap().as_ref() {
            sink.play();
            {
                let mut playing = self.playing.lock().unwrap();
                *playing = true;
            }
            let paused_pos = *self.paused_position.lock().unwrap();
            let now = Instant::now();
            let new_start = now
                .checked_sub(Duration::from_secs_f32(paused_pos))
                .unwrap_or(now);
            *self.start_time.lock().unwrap() = new_start;
            *self.is_paused.lock().unwrap() = false;
            return true;
        }
        false
    }

    fn stop(&self) -> bool {
        if let Some(old_sink) = self.sink.lock().unwrap().take() {
            old_sink.stop();
            *self.playing.lock().unwrap() = false;
            return true;
        }
        false
    }

    fn get_position(&self) -> f32 {
        if *self.is_paused.lock().unwrap() {
            return *self.paused_position.lock().unwrap();
        }
        self.start_time.lock().unwrap().elapsed().as_secs_f32()
    }

    // Crossfade between the old and new sinks over a crossfade interval.
    fn crossfade(old_sink: Option<Arc<Sink>>, new_sink: Arc<Sink>) {
        let crossfade_duration = Duration::from_secs(3);
        let fade_step = Duration::from_millis(100);
        let steps = (crossfade_duration.as_millis() / fade_step.as_millis()) as usize;
        thread::spawn(move || {
            for i in 0..=steps {
                let volume_new = i as f32 / steps as f32;
                new_sink.set_volume(volume_new);
                if let Some(ref sink) = old_sink {
                    sink.set_volume(1.0 - volume_new);
                }
                thread::sleep(fade_step);
            }
            if let Some(sink) = old_sink {
                sink.stop();
            }
        });
    }

    fn background_worker(
        receiver: Receiver<PlayerMessage>,
        stream_handle: OutputStreamHandle,
        buffer: Arc<Mutex<Option<StreamingBuffer>>>,
    ) {
        while let Ok(message) = receiver.recv() {
            match message {
                PlayerMessage::Load { path, position } => {
                    //println!("Loading file: {}", &path);
                    if let Ok(file) = fs::File::open(&path) {
                        let mut reader = BufReader::new(file);
                        if position > 0.0 {
                            let bytes_pos = (position * 44100.0 * 2.0) as u64;
                            let _ = reader.seek(SeekFrom::Start(bytes_pos));
                        }
                        let chunks = Arc::new(Mutex::new(Vec::new()));
                        let mut decoder: Option<Decoder<Cursor<Vec<u8>>>> = None;
                        let mut sample_rate = 44100;
                        let mut channels = 2;
                        let mut total_duration = Duration::from_secs(0);
                        let mut initial_data = Vec::new();
                        if reader.read_to_end(&mut initial_data).is_ok() && !initial_data.is_empty()
                        {
                            let cursor = Cursor::new(initial_data.clone());
                            if let Ok(dec) = Decoder::new(cursor) {
                                sample_rate = dec.sample_rate();
                                channels = dec.channels();
                                decoder = Some(dec);
                                let samples_count = initial_data.len() / (channels as usize * 2);
                                total_duration = Duration::from_secs_f64(
                                    samples_count as f64 / sample_rate as f64,
                                );
                            }
                        }
                        let _ = reader.seek(SeekFrom::Start(0));
                        {
                            // Preload a (possibly empty) initial chunk
                            let mut guard = chunks.lock().unwrap();
                            if let Some(ref mut dec) = decoder {
                                let samples: Vec<f32> =
                                    dec.take(0).map(|s| s as f32 / i16::MAX as f32).collect();
                                guard.push(AudioChunk { samples });
                            }
                        }
                        let streaming_buffer = StreamingBuffer {
                            chunks: Arc::clone(&chunks),
                            sample_rate,
                            channels,
                            total_duration,
                        };
                        {
                            let mut buf = buffer.lock().unwrap();
                            *buf = Some(streaming_buffer.clone());
                        }
                        // Create sink and append a streaming source.
                        if let Ok(raw_sink) = Sink::try_new(&stream_handle) {
                            raw_sink.set_volume(0.0);
                            let new_sink = Arc::new(raw_sink);
                            let source = StreamingSource {
                                buffer: Arc::new(Mutex::new(Some(streaming_buffer))),
                                current_chunk: 0,
                                position: 0,
                                chunks_processed: 0,
                            };
                            new_sink.append(source);
                            new_sink.play();
                            if let Ok(player_lock) = PLAYER.lock() {
                                if let Some(player) = player_lock.as_ref() {
                                    let old_sink = player.sink.lock().unwrap().take();
                                    AudioPlayer::crossfade(old_sink, Arc::clone(&new_sink));
                                    *player.sink.lock().unwrap() = Some(Arc::clone(&new_sink));
                                    *player.current_file.lock().unwrap() = path.clone();
                                    *player.start_time.lock().unwrap() = Instant::now();
                                    *player.playing.lock().unwrap() = true;
                                    *player.is_paused.lock().unwrap() = false;
                                }
                            }
                            // Spawn thread to buffer the rest of the audio in chunks.
                            let chunks_clone = Arc::clone(&chunks);
                            let file_path = path.clone();
                            thread::spawn(move || {
                                if let Ok(file) = fs::File::open(&file_path) {
                                    let mut reader = BufReader::new(file);
                                    let mut file_data = Vec::new();
                                    if reader.read_to_end(&mut file_data).is_ok() {
                                        let cursor = Cursor::new(file_data);
                                        if let Ok(decoder) = Decoder::new(cursor) {
                                            let mut samples =
                                                Vec::with_capacity(sample_rate as usize);
                                            for sample in decoder {
                                                samples.push(sample as f32 / i16::MAX as f32);
                                                if samples.len()
                                                    >= (sample_rate as usize * channels as usize)
                                                {
                                                    if let Ok(mut guard) = chunks_clone.lock() {
                                                        guard.push(AudioChunk {
                                                            samples: samples.clone(),
                                                        });
                                                    }
                                                    samples.clear();
                                                }
                                            }
                                            if !samples.is_empty() {
                                                if let Ok(mut guard) = chunks_clone.lock() {
                                                    guard.push(AudioChunk { samples });
                                                }
                                            }
                                        }
                                    }
                                }
                            });
                        }
                    } else {
                        println!("Failed to open file: {}", &path);
                    }
                }
                PlayerMessage::Seek(position) => {
                    if let Ok(buffer_guard) = buffer.lock() {
                        if let Some(ref buf) = *buffer_guard {
                            let target_sample_index = (position * buf.sample_rate as f32) as usize
                                * buf.channels as usize;
                            let (current_chunk, position_in_chunk) = {
                                let guard = buf.chunks.lock().unwrap();
                                let mut accumulated = 0;
                                let mut found = (0, 0);
                                for (i, chunk) in guard.iter().enumerate() {
                                    if accumulated + chunk.samples.len() > target_sample_index {
                                        found = (i, target_sample_index - accumulated);
                                        break;
                                    }
                                    accumulated += chunk.samples.len();
                                }
                                found
                            };
                            if let Ok(raw_sink) = Sink::try_new(&stream_handle) {
                                let new_sink = Arc::new(raw_sink);
                                let source = StreamingSource {
                                    buffer: Arc::new(Mutex::new(Some(buf.clone()))),
                                    current_chunk,
                                    position: position_in_chunk,
                                    chunks_processed: current_chunk,
                                };
                                new_sink.append(source);
                                new_sink.play();
                                if let Ok(player_lock) = PLAYER.lock() {
                                    if let Some(player) = player_lock.as_ref() {
                                        let old_sink = player.sink.lock().unwrap().take();
                                        AudioPlayer::crossfade(old_sink, Arc::clone(&new_sink));
                                        *player.sink.lock().unwrap() = Some(Arc::clone(&new_sink));
                                        let now = Instant::now();
                                        let new_start = now
                                            .checked_sub(Duration::from_secs_f32(position))
                                            .unwrap_or(now);
                                        *player.start_time.lock().unwrap() = new_start;
                                    }
                                }
                            }
                        }
                    }
                }
                PlayerMessage::Stop => break,
            }
        }
    }

    fn play(&self, path: &str) -> bool {
        self.stop();
        {
            let mut playing = self.playing.lock().unwrap();
            let mut paused = self.is_paused.lock().unwrap();
            *playing = true;
            *paused = false;
            *self.paused_position.lock().unwrap() = 0.0;
            *self.start_time.lock().unwrap() = Instant::now();
        }
        if let Ok(sender) = self.sender.lock() {
            sender
                .send(PlayerMessage::Load {
                    path: path.to_string(),
                    position: 0.0,
                })
                .is_ok()
        } else {
            false
        }
    }

    fn seek(&self, position: f32) -> bool {
        {
            if let Ok(sink_guard) = self.sink.lock() {
                if let Some(ref old) = *sink_guard {
                    old.stop();
                }
            }
            let now = Instant::now();
            let new_start = now
                .checked_sub(Duration::from_secs_f32(position))
                .unwrap_or(now);
            *self.start_time.lock().unwrap() = new_start;
        }
        if let Ok(sender) = self.sender.lock() {
            sender.send(PlayerMessage::Seek(position)).is_ok()
        } else {
            false
        }
    }
}

struct StreamingSource {
    buffer: Arc<Mutex<Option<StreamingBuffer>>>,
    current_chunk: usize,
    position: usize,
    chunks_processed: usize,
}

impl Source for StreamingSource {
    fn current_frame_len(&self) -> Option<usize> {
        None
    }

    fn total_duration(&self) -> Option<Duration> {
        if let Ok(buffer_guard) = self.buffer.lock() {
            if let Some(ref buf) = *buffer_guard {
                return Some(buf.total_duration);
            }
        }
        None
    }

    fn channels(&self) -> u16 {
        if let Ok(buffer_guard) = self.buffer.lock() {
            if let Some(ref buf) = *buffer_guard {
                return buf.channels;
            }
        }
        2
    }

    fn sample_rate(&self) -> u32 {
        if let Ok(buffer_guard) = self.buffer.lock() {
            if let Some(ref buf) = *buffer_guard {
                return buf.sample_rate;
            }
        }
        44100
    }
}

impl Iterator for StreamingSource {
    type Item = f32;

    fn next(&mut self) -> Option<Self::Item> {
        // Acquire locks briefly for each chunk iteration.
        let current_buffer = match self.buffer.lock() {
            Ok(b) => b.clone(),
            Err(_) => return None,
        };
        let buf = current_buffer?;
        let guard = buf.chunks.lock().unwrap();
        while self.current_chunk < guard.len() {
            if let Some(chunk) = guard.get(self.current_chunk) {
                if self.position < chunk.samples.len() {
                    let sample = chunk.samples[self.position];
                    self.position += 1;
                    return Some(sample);
                } else {
                    self.current_chunk += 1;
                    self.position = 0;
                    self.chunks_processed += 1;
                    continue;
                }
            }
            break;
        }
        // If we’ve processed some chunks, wait a moment and then try again.
        if self.chunks_processed > 0 && self.current_chunk >= guard.len() {
            drop(guard);
            thread::sleep(Duration::from_millis(10));
            return self.next();
        }
        None
    }
}

unsafe impl Send for AudioPlayer {}
unsafe impl Sync for AudioPlayer {}

#[frb(sync)]
pub fn initialize_player() -> bool {
    let mut state = PLAYER_STATE.lock().unwrap();
    if !state.initialized {
        let mut player = PLAYER.lock().unwrap();
        if player.is_none() {
            if let Some(new_player) = AudioPlayer::new() {
                *player = Some(new_player);
                state.initialized = true;
                return true;
            }
        }
    }
    false
}

static MP3_CONVERSION_POOL: Lazy<ThreadPool> =
    Lazy::new(|| ThreadPoolBuilder::new().num_threads(2).build().unwrap());

#[frb(sync)]
pub fn scan_music_directory(dir_path: String, auto_convert: bool) -> Vec<SongMetadata> {
    let mut songs = Vec::new();
    let mut conversion_paths = Vec::new();
    let in_playlist_mode = dir_path.contains(".adilists");

    // First pass: collect existing files and non-MP3s needing conversion
    for entry in WalkDir::new(&dir_path)
        .follow_links(true)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        if !in_playlist_mode
            && entry
                .path()
                .components()
                .any(|c| c.as_os_str() == ".adilists")
        {
            continue;
        }
        if let Some(ext) = entry.path().extension() {
            let ext_lower = ext.to_str().unwrap_or("").to_lowercase();
            match ext_lower.as_str() {
                "mp3" | "m4a" | "flac" => {
                    // Directly read metadata and add to songs
                    if let Some(metadata) = extract_metadata(entry.path()) {
                        songs.push(metadata);
                    }
                }
                "ogg" | "wav" => {
                    let original_path = entry.path().to_owned();
                    let cached_path = get_cached_mp3_path(&original_path);
                    if cached_path.exists() {
                        // Use original's metadata but set path to cached MP3
                        if let Some(mut metadata) = extract_metadata(&original_path) {
                            metadata.path = cached_path.to_string_lossy().into_owned();
                            songs.push(metadata);
                        }
                    } else {
                        conversion_paths.push((original_path, cached_path));
                    }
                }
                _ => (),
            }
        }
    }

    // Convert WAV/OGG files in parallel
    if !conversion_paths.is_empty() && auto_convert {
        let conv_path_clone = conversion_paths.clone();
        MP3_CONVERSION_POOL.spawn(move || {
            for (original, cached) in &conv_path_clone {
                let orig_str = original.to_string_lossy();
                let cache_str = cached.to_string_lossy();
                let status = Command::new("ffmpeg")
                    .args(&["-hide_banner", "-loglevel", "error", "-y", "-i", &orig_str])
                    .args(&[
                        "-codec:a",
                        "libmp3lame",
                        "-qscale:a",
                        "2",
                        "-map_metadata",
                        "0",
                        &cache_str,
                    ])
                    .status();
                if let Ok(status) = status {
                    if !status.success() {
                        eprintln!("Conversion failed for {}", orig_str);
                    }
                } else {
                    eprintln!("Failed to convert {}", orig_str);
                }
            }
        });
    }

    // Second pass: add converted WAV/OGG files with original metadata
    for (original, cached) in conversion_paths {
        if cached.exists() {
            if let Some(mut metadata) = extract_metadata(&original) {
                metadata.path = cached.to_string_lossy().into_owned();
                songs.push(metadata);
            }
        }
    }

    songs
}

fn extract_metadata(path: &Path) -> Option<SongMetadata> {
    let tag = Tag::default().read_from_path(path).ok()?;

    let title = tag
        .title()
        .map(|s| s.to_string())
        .unwrap_or_else(|| "Unknown Title".to_string());
    let artist_str = tag.artist().map(|s| s.to_string()).unwrap_or_default();
    let separators = SEPARATORS.read().unwrap();
    let pattern = separators
        .iter()
        .map(|s| regex::escape(s))
        .collect::<Vec<_>>()
        .join("|");
    let re = Regex::new(&format!(r"(?i){}", pattern)).unwrap();
    let artists: Vec<String> = re
        .split(&artist_str)
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();
    let artist = if artists.is_empty() {
        "Unknown Artist".to_string()
    } else {
        artists.join(", ")
    };
    let album = tag
        .album()
        .map(|a| a.title.to_string())
        .unwrap_or_else(|| "Unknown Album".to_string());
    let genre = tag
        .genre()
        .map(|s| s.to_string())
        .unwrap_or_else(|| "Unknown Genre".to_string());

    // Extract album art
    let album_art = tag.album_cover().map(|pic| {
        let art = BASE64.encode(&pic.data);
        if let Ok(player) = PLAYER.lock() {
            if let Some(p) = player.as_ref() {
                let mut cache = p.album_art_cache.lock().unwrap();
                cache.insert(path.to_string_lossy().to_string(), art.clone());
            }
        }
        art
    });

    // Extract duration using rodio's decoder
    let duration = {
        let file = std::fs::File::open(path).ok()?;
        let reader = BufReader::new(file);
        Decoder::new(reader)
            .ok()
            .and_then(|source| source.total_duration())
            .map(|d| d.as_secs())
            .unwrap_or(0)
    };

    Some(SongMetadata {
        title,
        artist,
        album,
        duration,
        path: path.to_string_lossy().to_string(),
        album_art,
        genre,
    })
}

#[frb(sync)]
pub fn play_song(path: String) -> bool {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        player.play(&path)
    } else {
        false
    }
}

#[frb(sync)]
pub fn pause_song() -> bool {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        player.pause()
    } else {
        false
    }
}

#[frb(sync)]
pub fn resume_song() -> bool {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        player.resume()
    } else {
        false
    }
}

#[frb(sync)]
pub fn stop_song() -> bool {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        player.stop()
    } else {
        false
    }
}

#[frb(sync)]
pub fn get_playback_position() -> f32 {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        player.get_position()
    } else {
        0.0
    }
}

#[frb(sync)]
pub fn seek_to_position(position: f32) -> bool {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        player.seek(position)
    } else {
        false
    }
}

#[frb(sync)]
pub fn skip_to_next(songs: Vec<String>, current_index: usize) -> bool {
    if current_index + 1 < songs.len() {
        if let Some(player) = PLAYER.lock().unwrap().as_ref() {
            return player.play(&songs[current_index + 1]);
        }
    }
    false
}

#[frb(sync)]
pub fn skip_to_previous(songs: Vec<String>, current_index: usize) -> bool {
    if current_index > 0 {
        if let Some(player) = PLAYER.lock().unwrap().as_ref() {
            return player.play(&songs[current_index - 1]);
        }
    }
    false
}

#[frb(sync)]
pub fn get_cached_album_art(path: String) -> Option<String> {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        player.album_art_cache.lock().unwrap().get(&path).cloned()
    } else {
        None
    }
}

#[frb(sync)]
pub fn get_current_song_path() -> Option<String> {
    PLAYER
        .lock()
        .unwrap()
        .as_ref()
        .map(|p| p.current_file.lock().unwrap().clone())
}

#[frb(sync)]
pub fn get_realtime_peaks() -> Vec<f32> {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        if let Some(ref buffer) = *player.buffer.lock().unwrap() {
            let guard = buffer.chunks.lock().unwrap();
            guard
                .iter()
                .map(|chunk| {
                    chunk
                        .samples
                        .iter()
                        .fold(0.0f32, |acc, &x| acc.max(x.abs()))
                })
                .collect()
        } else {
            Vec::new()
        }
    } else {
        Vec::new()
    }
}

#[frb(sync)]
pub fn is_playing() -> bool {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        *player.playing.lock().unwrap()
    } else {
        false
    }
}

/// Extracts waveform data from an MP3 file using FFmpeg to decode it to PCM data.
///
/// This function launches FFmpeg with arguments to decode [mp3_path] to 16-bit PCM (s16le)
/// using the given number of [channels] (default is 2). It then downsamples the resulting PCM
/// stream to return [sampleCount] normalized amplitude values (between 0 and 1).
///
/// Note: This requires FFmpeg to be installed on your Linux system.

#[frb(sync)]
pub fn extract_waveform_from_mp3(
    mp3_path: String,
    sample_count: Option<u32>,
    channels: Option<u32>,
) -> Result<Vec<f64>, String> {
    let sample_count = sample_count.unwrap_or(1000) as usize;
    let channels = channels.unwrap_or(2);
    let output = Command::new("ffmpeg")
        .args(&[
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            &mp3_path,
            "-f",
            "s16le",
            "-acodec",
            "pcm_s16le",
            "-ac",
            &channels.to_string(),
            "-",
        ])
        .output()
        .map_err(|e| format!("Failed to start ffmpeg: {}", e))?;
    if !output.status.success() {
        return Err(format!(
            "FFmpeg exited with code {}. Ensure FFmpeg is installed and the file exists.",
            output.status
        ));
    }
    let pcm_bytes = output.stdout;
    let sample_size_in_bytes = 2;
    let total_samples = pcm_bytes.len() / sample_size_in_bytes;
    let sample_frames = total_samples / channels as usize;
    if sample_frames == 0 {
        return Err("No samples found in file".to_string());
    }
    let step = max(1, sample_frames / sample_count);
    let mut waveform = Vec::with_capacity(sample_count);
    for frame in (0..sample_frames).step_by(step) {
        let mut sum = 0.0;
        let mut count = 0;
        for ch in 0..channels as usize {
            let offset = (frame * channels as usize + ch) * sample_size_in_bytes;
            if offset + sample_size_in_bytes > pcm_bytes.len() {
                break;
            }
            let sample_value =
                i16::from_le_bytes([pcm_bytes[offset], pcm_bytes[offset + 1]]) as f64;
            sum += sample_value.abs() / 32768.0;
            count += 1;
        }
        if count > 0 {
            waveform.push(sum / count as f64);
        }
    }
    Ok(waveform)
}

static SEPARATORS: Lazy<RwLock<Vec<String>>> = Lazy::new(|| {
    RwLock::new(vec![
        ",".to_string(),
        ";".to_string(),
        "/".to_string(),
        "&".to_string(),
        "feat.".to_string(),
        "ft.".to_string(),
        "vs.".to_string(),
    ])
});

#[frb(sync)]
pub fn add_separator(separator: String) -> Result<(), String> {
    let mut separators = SEPARATORS.write().unwrap();
    if separators.contains(&separator) {
        return Err("Separator already exists".to_string());
    }
    separators.push(separator);
    Ok(())
}

#[frb(sync)]
pub fn remove_separator(separator: &str) -> Result<(), String> {
    let mut separators = SEPARATORS.write().unwrap();
    let index = separators
        .iter()
        .position(|s| s == separator)
        .ok_or_else(|| "Separator not found".to_string())?;
    separators.remove(index);
    Ok(())
}

#[frb(sync)]
pub fn get_current_separators() -> Vec<String> {
    SEPARATORS.read().unwrap().clone()
}

#[frb(sync)]
pub fn reset_separators() {
    let mut separators = SEPARATORS.write().unwrap();
    *separators = vec![
        ",".to_string(),
        ";".to_string(),
        "/".to_string(),
        "&".to_string(),
        "feat.".to_string(),
        "ft.".to_string(),
        "vs.".to_string(),
    ];
}

#[frb(sync)]
pub fn set_separators(separators: Vec<String>) {
    let mut sep = SEPARATORS.write().unwrap();
    *sep = separators;
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Track {
    pub name: String,
    pub artist: String,
    pub genres: Vec<String>,
    pub album_name: String,
    pub cover_url: String,
}

// A global flag to cancel the download.
static CANCEL_DOWNLOAD: Lazy<AtomicBool> = Lazy::new(|| AtomicBool::new(false));

pub fn download_to_temp(query: String) -> Result<String, String> {
    // Reset cancellation flag at the start of the download.
    CANCEL_DOWNLOAD.store(false, Ordering::SeqCst);
    let (tx, rx) = mpsc::channel();

    std::thread::spawn(move || {
        let result = (|| {
            let temp_dir = std::env::temp_dir();
            let temp_path = temp_dir
                .to_str()
                .ok_or("Failed to get temp directory")?
                .to_string();

            let output_path = format!("{}/{{artist}} - {{title}}.mp3", temp_path);

            let mut child: Child = Command::new("spotdl")
                .args(&[
                    "--no-cache",
                    "--format",
                    "mp3",
                    "--output",
                    &output_path,
                    &query,
                ])
                .spawn()
                .map_err(|e| format!("Failed to start download: {}", e))?;

            loop {
                // Check cancellation flag
                if CANCEL_DOWNLOAD.load(Ordering::SeqCst) {
                    // If cancellation is requested, kill the process and return early.
                    let _ = child.kill();
                    return Err("Download cancelled".into());
                }

                match child.try_wait() {
                    Ok(Some(status)) => {
                        if !status.success() {
                            return Err(format!("Download failed with exit code: {}", status));
                        }
                        break;
                    }
                    Ok(None) => {
                        // Process still running, sleep briefly before polling again.
                        // Best I could think of on 4 hours of sleep
                        std::thread::sleep(Duration::from_millis(100));
                    }
                    Err(e) => return Err(format!("Error waiting for download process: {}", e)),
                }
            }

            let dir = std::fs::read_dir(&temp_path)
                .map_err(|e| format!("Error reading temp dir: {}", e))?;

            for entry in dir {
                let entry = entry.map_err(|e| format!("Error reading entry: {}", e))?;
                if let Some(ext) = entry.path().extension() {
                    if ext == "mp3" {
                        return Ok(entry.path().to_string_lossy().into_owned());
                    }
                }
            }

            Err("No MP3 file found after download".into())
        })();
        tx.send(result).unwrap();
    });

    rx.recv().unwrap()
}

pub fn cancel_download() {
    CANCEL_DOWNLOAD.store(true, Ordering::SeqCst);
}

// Currently unused because it is an absolute pain to wait for all the songs to come back but is
// now a setting
#[frb(sync)]
pub fn clear_mp3_cache() -> bool {
    let cache_dir = get_mp3_cache_dir();
    if cache_dir.exists() {
        fs::remove_dir_all(&cache_dir).is_ok()
    } else {
        true
    }
}

// Here as a temp (hopefully) fix to stop > 1 artist crashing mpris
#[frb(sync)]
pub fn get_artist_via_ffprobe(file_path: String) -> Result<Vec<String>, String> {
    let output = Command::new("ffprobe")
        .args(&[
            "-v",
            "error",
            "-show_entries",
            "format_tags=artist",
            "-of",
            "default=nw=1:nk=1",
            &file_path,
        ])
        .output()
        .map_err(|e| format!("Failed to start ffprobe: {}", e))?;

    if !output.status.success() {
        return Ok(vec![]);
    }

    let artist_line = String::from_utf8_lossy(&output.stdout).trim().to_string();

    if artist_line.is_empty() {
        return Ok(vec![]);
    }

    let separators = SEPARATORS.read().unwrap();

    let joined = separators
        .iter()
        .map(|s| regex::escape(s))
        .collect::<Vec<_>>()
        .join("|");

    let regex = Regex::new(&format!(r"\s*(?:{})\s*", joined)).map_err(|e| e.to_string())?;

    Ok(regex
        .split(&artist_line)
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect())
}
