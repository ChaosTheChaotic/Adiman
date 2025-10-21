use crate::api::utils::fpre;
use atomic_float::AtomicF32;
use audiotags::Tag;
use cd_audio::{
    sget_cd_stream_first_sector, sget_cd_stream_last_sector, sget_devices, sget_track_meta,
    sopen_cd_stream, sread_cd_stream, sseek_cd_stream, strack_duration, strack_num, sverify_audio,
    SCDStream,
};
use once_cell::sync::Lazy;
use rayon::prelude::*;
use rayon::{ThreadPool, ThreadPoolBuilder};
use regex::Regex;
use rodio::{
    cpal::traits::{DeviceTrait, HostTrait},
    Decoder, OutputStream, OutputStreamBuilder, Sink, Source,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    cmp::max,
    collections::{HashMap, HashSet},
    env::temp_dir,
    fmt,
    fs::{self, read_dir},
    io::{BufReader, Cursor, Read, Seek, SeekFrom},
    path::{Path, PathBuf},
    process::{Child, Command},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, Sender},
        Arc, Mutex, RwLock,
    },
    thread,
    time::{Duration, Instant},
};
use walkdir::WalkDir;

struct SafeSCDStream(SCDStream);
unsafe impl Send for SafeSCDStream {}

struct CDStreamSource {
    stream: SafeSCDStream,
    raw_buffer: Vec<u8>,
    samples: Vec<f32>,
    pos: usize,
    sample_rate: u32,
    channels: u16,
    total_duration: Duration,
    first_sector: i32,
    last_sector: i32,
}

impl CDStreamSource {
    fn new(device: &str, track: i32) -> Result<Self, String> {
        let stream = sopen_cd_stream(device, track).ok_or("Failed to open CD stream")?;

        let duration_secs = strack_duration(device.to_string(), track);
        if duration_secs < 0 {
            return Err("Failed to get track duration".to_string());
        }
        let total_duration = Duration::from_secs(duration_secs as u64);
        let first_sector = sget_cd_stream_first_sector(&stream);
        let last_sector = sget_cd_stream_last_sector(&stream);

        // Create buffer for 500 sectors (about 1.1MB)
        let buffer_capacity = 2352 * 1000;
        let raw_buffer = vec![0; buffer_capacity];

        Ok(Self {
            stream: SafeSCDStream(stream),
            raw_buffer,
            samples: Vec::new(), // Start with empty samples
            pos: 0,
            sample_rate: 44100,
            channels: 2,
            total_duration,
            first_sector,
            last_sector,
        })
    }

    fn fill_buffer(&mut self) -> Result<(), String> {
        let mut stream = &mut self.stream.0;
        let max_sectors = self.raw_buffer.len() / 2352;
        let sectors = max_sectors as i32;

        let required_len = sectors as usize * 2352;
        let buffer_slice = &mut self.raw_buffer[0..required_len];
        let read = sread_cd_stream(&mut stream, buffer_slice, sectors);

        if read < 0 {
            return Err("Error reading CD stream".into());
        } else if read == 0 {
            return Err("End of stream".into());
        }

        let bytes_read = read as usize * 2352;

        // Convert entire buffer to samples at once
        self.samples = buffer_slice[..bytes_read]
            .chunks_exact(2)
            .map(|chunk| i16::from_le_bytes([chunk[0], chunk[1]]) as f32 / 32768.0)
            .collect();

        self.pos = 0;
        Ok(())
    }

    fn seek(&mut self, time: Duration) -> Result<(), String> {
        let seconds = time.as_secs_f32();
        let sector_offset = (seconds * 75.0) as i32; // 75 sectors per second
        let target_sector = self.first_sector + sector_offset;

        if target_sector < self.first_sector || target_sector > self.last_sector {
            return Err("Seek out of bounds".to_string());
        }

        let mut stream = &mut self.stream.0;
        if sseek_cd_stream(&mut stream, target_sector) {
            // Reset buffer state completely
            self.samples.clear();
            self.pos = 0;
            Ok(())
        } else {
            Err("Seek failed".to_string())
        }
    }
    //pub fn first_sector(&self) -> i32 { self.first_sector }
    //pub fn last_sector(&self) -> i32 { self.last_sector }
}

impl Source for CDStreamSource {
    fn current_span_len(&self) -> Option<usize> {
        None
    }
    fn channels(&self) -> u16 {
        self.channels
    }
    fn sample_rate(&self) -> u32 {
        self.sample_rate
    }
    fn total_duration(&self) -> Option<Duration> {
        Some(self.total_duration)
    }
}

impl Iterator for CDStreamSource {
    type Item = f32;

    fn next(&mut self) -> Option<Self::Item> {
        if self.pos >= self.samples.len() {
            if self.fill_buffer().is_err() {
                return None;
            }
            // Check again after refill
            if self.pos >= self.samples.len() {
                return None;
            }
        }

        let sample = self.samples[self.pos];
        self.pos += 1;
        Some(sample)
    }
}

pub fn track_num(device: String) -> i32 {
    return strack_num(device);
}

pub fn list_audio_cds() -> Vec<String> {
    let sdev_list = sget_devices();
    sdev_list
        .inner
        .clone()
        .into_iter()
        .filter(|dev| sverify_audio(dev.clone()))
        .collect()
}

pub fn get_cd_track_metadata(device: String, track: u32) -> SongMetadata {
    let track_i32 = track as i32;
    let (title, artist, genre) = sget_track_meta(device.clone(), track_i32);
    let duration = strack_duration(device.clone(), track_i32) as u64;

    SongMetadata {
        title,
        artist,
        album: "Unknown Album".to_string(),
        duration,
        path: format!("cdda://{}/track{}", device, track),
        album_art: None,
        genre,
    }
}

fn get_mp3_cache_dir() -> PathBuf {
    let mut cache_dir = temp_dir();
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
    PreloadNext { path: String },
    Seek(f32),
    Stop,
    SwitchToPreloaded,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SongMetadata {
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: u64,
    pub path: String,
    pub album_art: Option<Vec<u8>>,
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
static FADE_IN: AtomicBool = AtomicBool::new(false);
static CUR_VOL: AtomicF32 = AtomicF32::new(1.0);

pub fn set_fadein(value: bool) {
    FADE_IN.store(value, Ordering::SeqCst);
}

pub fn get_cvol() -> f32 {
    return CUR_VOL.load(Ordering::SeqCst);
}

pub fn list_audio_devices() -> Vec<String> {
    let host = rodio::cpal::default_host();
    match host.devices() {
        Ok(devices) => devices.filter_map(|d| d.name().ok()).collect(),
        Err(e) => {
            eprintln!("Error listing audio devices: {}", e);
            Vec::new()
        }
    }
}

struct AudioPlayer {
    sink: Mutex<Option<Arc<Sink>>>,
    current_file: Mutex<String>,
    start_time: Mutex<Instant>,
    playing: Mutex<bool>,
    album_art_cache: Mutex<HashMap<String, Vec<u8>>>,
    sender: Mutex<Sender<PlayerMessage>>,
    buffer: Arc<Mutex<Option<StreamingBuffer>>>,
    paused_position: Mutex<f32>,
    is_paused: Mutex<bool>,
    next_sink: Mutex<Option<Arc<Sink>>>,
    next_buffer: Arc<Mutex<Option<StreamingBuffer>>>,
    next_path: Mutex<Option<String>>,
    preload_monitor: Arc<AtomicBool>,
}

impl fmt::Debug for AudioPlayer {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("AudioPlayer")
            .field("sink", &"<SinkMutex>")
            .finish()
    }
}

impl AudioPlayer {
    fn new() -> Option<Self> {
        if let Ok(stream) = OutputStreamBuilder::open_default_stream() {
            // Create a channel for commands
            let (tx, rx) = mpsc::channel();
            let buffer = Arc::new(Mutex::new(None));
            let buffer_clone = Arc::clone(&buffer);
            let mixer = stream.mixer().clone();
            let preload_monitor = Arc::new(AtomicBool::new(false));
            let transition_threshold = Arc::new(AtomicF32::new(0.0));

            // Spawn monitoring thread
            let preload_monitor_clone = Arc::clone(&preload_monitor);
            let transition_threshold_clone = Arc::clone(&transition_threshold);
            let tx_clone = tx.clone();

            thread::spawn(move || {
                Self::position_monitor(preload_monitor_clone, transition_threshold_clone, tx_clone)
            });
            // Spawn the background worker with a cloned mixer and buffer.
            thread::spawn(move || Self::background_worker(rx, mixer, buffer_clone));
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
                    next_sink: Mutex::new(None),
                    next_buffer: Arc::new(Mutex::new(None)),
                    next_path: Mutex::new(Some(String::new())),
                    preload_monitor,
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
        let current_vol = CUR_VOL.load(Ordering::SeqCst);
        if FADE_IN.load(Ordering::SeqCst) {
            let crossfade_duration = Duration::from_secs(3);
            let fade_step = Duration::from_millis(100);
            let steps = (crossfade_duration.as_millis() / fade_step.as_millis()) as usize;
            thread::spawn(move || {
                for i in 0..=steps {
                    let volume_new = i as f32 / steps as f32;
                    new_sink.set_volume(volume_new);
                    if let Some(ref sink) = old_sink {
                        sink.set_volume(current_vol - volume_new);
                    }
                    thread::sleep(fade_step);
                }
                if let Some(sink) = old_sink {
                    sink.stop();
                }
            });
        } else {
            new_sink.set_volume(current_vol);
            if let Some(sink) = old_sink {
                sink.stop();
            }
        }
    }

    fn parse_cd_path(path: &str) -> Result<(String, i32), String> {
        let re = Regex::new(r"cdda://(.+)/track(\d+)").unwrap();
        let caps = re.captures(path).ok_or("Invalid CD path")?;
        let device = caps[1].to_string();
        let track = caps[2].parse::<i32>().map_err(|_| "Invalid track")?;
        Ok((device, track))
    }

    fn background_worker(
        receiver: Receiver<PlayerMessage>,
        mixer: rodio::mixer::Mixer,
        buffer: Arc<Mutex<Option<StreamingBuffer>>>,
    ) {
        while let Ok(message) = receiver.recv() {
            match message {
                PlayerMessage::Load { path, position } => {
                    if path.starts_with("cdda://") {
                        // Parse CD path
                        let path_after_scheme = &path[7..];
                        let track_start = path_after_scheme.rfind("track");
                        if let Some(track_index) = track_start {
                            let device = path_after_scheme[..track_index].trim_end_matches('/');
                            let track_str = &path_after_scheme[track_index..];

                            if !track_str.starts_with("track") {
                                println!("Invalid track in CD path: {}", path);
                                continue;
                            }

                            let track_num = match track_str[5..].parse::<i32>() {
                                Ok(n) => n,
                                Err(_) => {
                                    println!("Invalid track number in CD path: {}", path);
                                    continue;
                                }
                            };

                            // Warn about seek position
                            if position != 0.0 {
                                println!(
                                    "Warning: Seeking in CD tracks is not supported (yet). Starting from beginning."
                                );
                            }

                            // Create CD source
                            match CDStreamSource::new(device, track_num) {
                                Ok(source) => {
                                    let new_sink = Arc::new(Sink::connect_new(&mixer));
                                    new_sink.set_volume(0.0);
                                    new_sink.append(source);
                                    new_sink.play();

                                    // Clear buffer for CD track
                                    {
                                        let mut buf = buffer.lock().unwrap();
                                        *buf = None;
                                    }

                                    // Update player state
                                    if let Ok(player_lock) = PLAYER.lock() {
                                        if let Some(player) = player_lock.as_ref() {
                                            let old_sink = player.sink.lock().unwrap().take();
                                            AudioPlayer::crossfade(old_sink, Arc::clone(&new_sink));
                                            *player.sink.lock().unwrap() =
                                                Some(Arc::clone(&new_sink));
                                            *player.current_file.lock().unwrap() = path.clone();
                                            *player.start_time.lock().unwrap() = Instant::now();
                                            *player.playing.lock().unwrap() = true;
                                            *player.is_paused.lock().unwrap() = false;
                                        }
                                    }
                                }
                                Err(e) => println!("Failed to open CD stream: {}", e),
                            }
                        }
                    } else {
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
                            if reader.read_to_end(&mut initial_data).is_ok()
                                && !initial_data.is_empty()
                            {
                                let cursor = Cursor::new(initial_data.clone());
                                if let Ok(dec) = Decoder::try_from(cursor) {
                                    sample_rate = dec.sample_rate();
                                    channels = dec.channels();
                                    total_duration =
                                        dec.total_duration().unwrap_or(Duration::from_secs(0));
                                    decoder = Some(dec);
                                }
                            }
                            let _ = reader.seek(SeekFrom::Start(0));
                            {
                                // Preload a (possibly empty) initial chunk
                                let mut guard = chunks.lock().unwrap();
                                if let Some(ref mut dec) = decoder {
                                    let samples: Vec<f32> = dec.take(0).map(|s| s).collect();
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
                            let new_sink = Arc::new(Sink::connect_new(&mixer));
                            new_sink.set_volume(0.0);
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
                                        if let Ok(decoder) = Decoder::try_from(cursor) {
                                            let mut samples =
                                                Vec::with_capacity(sample_rate as usize);
                                            for sample in decoder {
                                                samples.push(sample);
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
                        } else {
                            println!("Failed to open file: {}", &path);
                        }
                    }
                }
                PlayerMessage::PreloadNext { path } => {
                    if path.starts_with("cdda://") {
                        break;
                    }
                    if let Ok(file) = fs::File::open(&path) {
                        let mut reader = BufReader::new(file);
                        let chunks = Arc::new(Mutex::new(Vec::new()));
                        let mut decoder: Option<Decoder<Cursor<Vec<u8>>>> = None;
                        let mut sample_rate = 44100;
                        let mut channels = 2;
                        let mut total_duration = Duration::from_secs(0);
                        let mut initial_data = Vec::new();
                        if reader.read_to_end(&mut initial_data).is_ok() && !initial_data.is_empty()
                        {
                            let cursor = Cursor::new(initial_data.clone());
                            if let Ok(dec) = Decoder::try_from(cursor) {
                                sample_rate = dec.sample_rate();
                                channels = dec.channels();
                                total_duration =
                                    dec.total_duration().unwrap_or(Duration::from_secs(0));
                                decoder = Some(dec);
                            }
                        }
                        let _ = reader.seek(SeekFrom::Start(0));
                        {
                            // Preload a (possibly empty) initial chunk
                            let mut guard = chunks.lock().unwrap();
                            if let Some(ref mut dec) = decoder {
                                let samples: Vec<f32> = dec.take(0).map(|s| s).collect();
                                guard.push(AudioChunk { samples });
                            }
                        }
                        let streaming_buffer = StreamingBuffer {
                            chunks: Arc::clone(&chunks),
                            sample_rate,
                            channels,
                            total_duration,
                        };
                        let stbuf_clone = streaming_buffer.clone();
                        // Create sink and append a streaming source.
                        let new_sink = Arc::new(Sink::connect_new(&mixer));
                        new_sink.set_volume(0.0);
                        let source = StreamingSource {
                            buffer: Arc::new(Mutex::new(Some(streaming_buffer))),
                            current_chunk: 0,
                            position: 0,
                            chunks_processed: 0,
                        };
                        new_sink.append(source);
                        new_sink.pause();
                        if let Ok(player_lock) = PLAYER.lock() {
                            if let Some(player) = player_lock.as_ref() {
                                *player.next_sink.lock().unwrap() = Some(Arc::clone(&new_sink));
                                *player.next_buffer.lock().unwrap() = Some(stbuf_clone);
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
                                    if let Ok(decoder) = Decoder::try_from(cursor) {
                                        let mut samples = Vec::with_capacity(sample_rate as usize);
                                        for sample in decoder {
                                            samples.push(sample);
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
                    } else {
                        println!("Failed to open file: {}", &path);
                    }
                }
                PlayerMessage::Seek(position) => {
                    let current_path = {
                        if let Ok(player_lock) = PLAYER.lock() {
                            if let Some(player) = player_lock.as_ref() {
                                player.current_file.lock().unwrap().clone()
                            } else {
                                String::new()
                            }
                        } else {
                            String::new()
                        }
                    };
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
                            let new_sink = Arc::new(Sink::connect_new(&mixer));
                            let source = StreamingSource {
                                buffer: Arc::new(Mutex::new(Some(buf.clone()))),
                                current_chunk,
                                position: position_in_chunk,
                                chunks_processed: current_chunk,
                            };
                            new_sink.append(source);
                            let should_play = {
                                if let Ok(player_lock) = PLAYER.lock() {
                                    player_lock
                                        .as_ref()
                                        .map(|p| !*p.is_paused.lock().unwrap())
                                        .unwrap_or(true)
                                } else {
                                    true
                                }
                            };

                            if should_play {
                                new_sink.play();
                            } else {
                                new_sink.pause();
                            }
                            if let Ok(player_lock) = PLAYER.lock() {
                                if let Some(player) = player_lock.as_ref() {
                                    let old_sink = player.sink.lock().unwrap().take();
                                    AudioPlayer::crossfade(old_sink, Arc::clone(&new_sink));
                                    *player.sink.lock().unwrap() = Some(Arc::clone(&new_sink));
                                }
                            }
                            if should_play {
                                if let Ok(player_lock) = PLAYER.lock() {
                                    if let Some(player) = player_lock.as_ref() {
                                        let now = Instant::now();
                                        let new_start = now
                                            .checked_sub(Duration::from_secs_f32(position))
                                            .unwrap_or(now);
                                        *player.start_time.lock().unwrap() = new_start;
                                    }
                                }
                            }
                        } else if current_path.starts_with("cdda://") {
                            // CD seek handling
                            if let Ok(player_lock) = PLAYER.lock() {
                                if let Some(player) = player_lock.as_ref() {
                                    let current_path = player.current_file.lock().unwrap().clone();

                                    // Parse device and track from path
                                    let (device, track) = Self::parse_cd_path(&current_path)
                                        .expect("Failed to parse CD path");

                                    // Create new source at seek position
                                    let mut source = CDStreamSource::new(&device, track)
                                        .expect("Failed to get new source");
                                    source
                                        .seek(Duration::from_secs_f32(position))
                                        .expect("Failed to seek");

                                    // Create new sink and play
                                    let new_sink = Arc::new(Sink::connect_new(&mixer));
                                    new_sink.append(source);
                                    new_sink.play();

                                    // Crossfade and update state
                                    let old_sink = player.sink.lock().unwrap().take();
                                    AudioPlayer::crossfade(old_sink, Arc::clone(&new_sink));
                                    *player.sink.lock().unwrap() = Some(Arc::clone(&new_sink));

                                    // Update start time to reflect the seek position
                                    let now = Instant::now();
                                    *player.start_time.lock().unwrap() = now
                                        .checked_sub(Duration::from_secs_f32(position))
                                        .unwrap_or(now);

                                    // Reset pause state
                                    *player.is_paused.lock().unwrap() = false;
                                    *player.paused_position.lock().unwrap() = 0.0;
                                }
                            }
                        }
                    }
                }
                PlayerMessage::SwitchToPreloaded => {
                    if let Ok(player_lock) = PLAYER.lock() {
                        if let Some(player) = player_lock.as_ref() {
                            player.switch_to_preloaded();
                        }
                    }
                }
                PlayerMessage::Stop => break,
            }
        }
    }

    fn switch_to_preloaded(&self) -> bool {
        let (new_sink, new_buffer, new_path) = {
            let next_sink = self.next_sink.lock().unwrap().take();
            let next_buffer = self.next_buffer.lock().unwrap().take();
            let next_path = self.next_path.lock().unwrap().take();
            (next_sink, next_buffer, next_path)
        };

        if let (Some(sink), Some(buffer), Some(path)) = (new_sink, new_buffer, new_path) {
            // Get current volume for seamless transition
            let current_volume = CUR_VOL.load(Ordering::SeqCst);

            // Stop monitoring temporarily
            self.preload_monitor.store(false, Ordering::SeqCst);

            // Switch to preloaded track
            let old_sink = self.sink.lock().unwrap().take();

            // Set volume and start playback
            sink.set_volume(current_volume);
            sink.play();

            // Update player state
            *self.sink.lock().unwrap() = Some(sink);
            *self.buffer.lock().unwrap() = Some(buffer);
            *self.current_file.lock().unwrap() = path;
            *self.start_time.lock().unwrap() = Instant::now();
            *self.playing.lock().unwrap() = true;
            *self.is_paused.lock().unwrap() = false;

            // Stop old sink after brief overlap for seamless transition
            if let Some(old) = old_sink {
                thread::spawn(move || {
                    thread::sleep(Duration::from_millis(50)); // Brief overlap
                    old.stop();
                });
            }

            // Restart monitoring for next preload
            self.preload_monitor.store(true, Ordering::SeqCst);

            true
        } else {
            false
        }
    }

    fn position_monitor(
        monitor_active: Arc<AtomicBool>,
        threshold: Arc<AtomicF32>,
        sender: Sender<PlayerMessage>,
    ) {
        loop {
            if monitor_active.load(Ordering::SeqCst) {
                if let Ok(player_lock) = PLAYER.lock() {
                    if let Some(player) = player_lock.as_ref() {
                        let position = player.get_position();
                        let has_preloaded = player.next_sink.lock().unwrap().is_some();

                        if has_preloaded {
                            // Get current track duration
                            let duration = {
                                if let Ok(buffer_guard) = player.buffer.lock() {
                                    buffer_guard
                                        .as_ref()
                                        .map(|buf| buf.total_duration.as_secs_f32())
                                        .unwrap_or(0.0)
                                } else {
                                    0.0
                                }
                            };

                            let threshold_secs = threshold.load(Ordering::SeqCst);

                            // Check if we're within threshold of the end
                            if duration > 0.0 && (duration - position) <= threshold_secs {
                                let _ = sender.send(PlayerMessage::SwitchToPreloaded);
                                monitor_active.store(false, Ordering::SeqCst);
                            }
                        }
                    }
                }
            }

            thread::sleep(Duration::from_millis(100)); // Check every 100ms
        }
    }

    // Modified play method to start monitoring
    fn play(&self, path: &str) -> bool {
        self.stop();
        {
            let mut playing = self.playing.lock().unwrap();
            let mut paused = self.is_paused.lock().unwrap();
            *playing = true;
            *paused = false;
            *self.paused_position.lock().unwrap() = 0.0;
            *self.start_time.lock().unwrap() = Instant::now();

            // Start position monitoring for preload transitions
            self.preload_monitor.store(true, Ordering::SeqCst);
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
            // Update paused position if paused, otherwise update start time
            let is_paused = *self.is_paused.lock().unwrap();
            if is_paused {
                *self.paused_position.lock().unwrap() = position;
            } else {
                let now = Instant::now();
                let new_start = now
                    .checked_sub(Duration::from_secs_f32(position))
                    .unwrap_or(now);
                *self.start_time.lock().unwrap() = new_start;
            }
        }
        if let Ok(sender) = self.sender.lock() {
            sender.send(PlayerMessage::Seek(position)).is_ok()
        } else {
            false
        }
    }
    fn set_volume(&self, volume: f32) -> bool {
        if let Some(sink) = self.sink.lock().unwrap().as_ref() {
            sink.set_volume(volume);
            true
        } else {
            false
        }
    }
}

impl Drop for AudioPlayer {
    fn drop(&mut self) {
        let _ = self.sender.lock().unwrap().send(PlayerMessage::Stop);
    }
}

struct StreamingSource {
    buffer: Arc<Mutex<Option<StreamingBuffer>>>,
    current_chunk: usize,
    position: usize,
    chunks_processed: usize,
}

impl Source for StreamingSource {
    fn current_span_len(&self) -> Option<usize> {
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

pub fn initialize_player() -> bool {
    dotenvy::dotenv().ok();
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

pub fn write_meta(meta: &SongMetadata) -> Result<(), String> {
    let mut tag = match Tag::new().read_from_path(meta.path.clone()) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("{e}");
            return Err(format!("Error reading tag: {e}"));
        }
    };
    tag.set_title(&meta.title);
    tag.set_artist(&meta.artist);
    tag.set_genre(&meta.genre);
    tag.set_album_title(&meta.album);
    match tag.write_to_path(&meta.path.clone()) {
        Ok(_) => Ok(()),
        Err(e) => {
            eprintln!("{e}");
            Err(format!("Error writing tag to path: {e}"))
        }
    }
}

fn extract_metadata(path: &Path) -> Option<SongMetadata> {
    let tag = Tag::default().read_from_path(path).ok();

    let title = tag
        .as_ref()
        .and_then(|t| t.title().map(|s| s.to_string()))
        .unwrap_or_else(|| {
            format!(
                "Unknown Title - {}",
                fpre(path)
                    .unwrap_or_else(|| path.as_os_str())
                    .to_string_lossy()
                    .to_string()
            )
        });
    let artist_str = tag
        .as_ref()
        .and_then(|t| t.artist().map(|s| s.to_string()))
        .unwrap_or_default();

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
        match get_artist_via_ffprobe(path.to_string_lossy().to_string()) {
            Ok(artists) if !artists.is_empty() => artists.join(", "),
            _ => "Unknown Artist".to_string(),
        }
    } else {
        artists.join(", ")
    };

    let album = tag
        .as_ref()
        .and_then(|t| t.album().map(|a| a.title.to_string()))
        .unwrap_or_else(|| "Unknown Album".to_string());

    let genre = tag
        .as_ref()
        .and_then(|t| t.genre().map(|s| s.to_string()))
        .unwrap_or_else(|| "Unknown Genre".to_string());

    let album_art = tag.as_ref().and_then(|t| t.album_cover()).map(|pic| {
        let art_bytes = pic.data.to_vec();
        if let Ok(player) = PLAYER.lock() {
            if let Some(p) = player.as_ref() {
                let mut cache = p.album_art_cache.lock().unwrap();
                cache.insert(path.to_string_lossy().to_string(), art_bytes.clone());
            }
        }
        art_bytes
    });

    // Extract duration (fallback to 0 if decoding fails)
    let duration = {
        if let Ok(file) = fs::File::open(path) {
            Decoder::try_from(file)
                .ok()
                .and_then(|source| source.total_duration().map(|d| d.as_secs()))
                .unwrap_or(0)
        } else {
            0
        }
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

pub fn play_song(path: String) -> bool {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        player.play(&path)
    } else {
        false
    }
}

pub fn pause_song() -> bool {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        player.pause()
    } else {
        false
    }
}

pub fn resume_song() -> bool {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        player.resume()
    } else {
        false
    }
}

pub fn stop_song() -> bool {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        player.stop()
    } else {
        false
    }
}

pub fn set_volume(volume: f32) -> bool {
    CUR_VOL.store(volume, Ordering::SeqCst);
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        player.set_volume(volume.clamp(0.0, 1.0))
    } else {
        false
    }
}

pub fn get_playback_position() -> f32 {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        player.get_position()
    } else {
        0.0
    }
}

pub fn seek_to_position(position: f32) -> bool {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        player.seek(position)
    } else {
        false
    }
}

pub fn skip_to_next(songs: Vec<String>, current_index: usize) -> bool {
    if current_index + 1 < songs.len() {
        if let Some(player) = PLAYER.lock().unwrap().as_ref() {
            return player.play(&songs[current_index + 1]);
        }
    }
    false
}

pub fn skip_to_previous(songs: Vec<String>, current_index: usize) -> bool {
    if current_index > 0 {
        if let Some(player) = PLAYER.lock().unwrap().as_ref() {
            return player.play(&songs[current_index - 1]);
        }
    }
    false
}

pub fn get_cached_album_art(path: String) -> Option<Vec<u8>> {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        player.album_art_cache.lock().unwrap().get(&path).cloned()
    } else {
        None
    }
}

pub fn get_current_song_path() -> Option<String> {
    PLAYER
        .lock()
        .unwrap()
        .as_ref()
        .map(|p| p.current_file.lock().unwrap().clone())
}

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

pub fn add_separator(separator: String) -> Result<(), String> {
    let mut separators = SEPARATORS.write().unwrap();
    if separators.contains(&separator) {
        return Err("Separator already exists".to_string());
    }
    separators.push(separator);
    Ok(())
}

pub fn remove_separator(separator: &str) -> Result<(), String> {
    let mut separators = SEPARATORS.write().unwrap();
    let index = separators
        .iter()
        .position(|s| s == separator)
        .ok_or_else(|| "Separator not found".to_string())?;
    separators.remove(index);
    Ok(())
}

pub fn get_current_separators() -> Vec<String> {
    SEPARATORS.read().unwrap().clone()
}

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

pub fn download_to_temp(query: String, flags: Option<String>) -> Result<String, String> {
    // Reset cancellation flag at the start of the download.
    CANCEL_DOWNLOAD.store(false, Ordering::SeqCst);
    let (tx, rx) = mpsc::channel();

    thread::spawn(move || {
        let result = (|| {
            let temp_dir = temp_dir();
            let temp_path = temp_dir
                .to_str()
                .ok_or("Failed to get temp directory")?
                .to_string();

            let output_path = format!("{}/{{artist}} - {{title}}.mp3", temp_path);

            let mut cmd = Command::new("spotdl");
            cmd.args(&[
                "download",
                &query,
                "--log-level",
                "DEBUG",
                "--no-cache",
                //"--format",
                //"mp3",
                "--output",
                &output_path,
            ]);

            // Add flags if they exist, split them into separate arguments
            if let Some(flags_str) = flags {
                for flag in flags_str.split_whitespace() {
                    cmd.arg(flag);
                }
            }
            let mut child: Child = cmd
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
                        thread::sleep(Duration::from_millis(100));
                    }
                    Err(e) => return Err(format!("Error waiting for download process: {}", e)),
                }
            }

            let dir = read_dir(&temp_path).map_err(|e| format!("Error reading temp dir: {}", e))?;

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
pub fn clear_mp3_cache() -> bool {
    let cache_dir = get_mp3_cache_dir();
    if cache_dir.exists() {
        fs::remove_dir_all(&cache_dir).is_ok()
    } else {
        true
    }
}

// Here as a temp (hopefully) fix to stop > 1 artist crashing mpris until I can find a better way
// to do it
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

fn parse_lrc_metadata(
    content: &str,
) -> Option<(String, String, String, String, String, Vec<String>)> {
    let mut title = None;
    let mut artist = None;
    let mut path = None;
    let mut genre = None;
    let mut album = None;
    let mut lyrics = Vec::new();

    for line in content.lines() {
        if line.starts_with("#TITLE: ") {
            title = Some(line["#TITLE: ".len()..].trim().to_string());
        } else if line.starts_with("#ARTIST: ") {
            artist = Some(line["#ARTIST: ".len()..].trim().to_string());
        } else if line.starts_with("#PATH: ") {
            path = Some(line["#PATH: ".len()..].trim().to_string());
        } else if line.starts_with("#GENRE: ") {
            genre = Some(line["#GENRE: ".len()..].trim().to_string());
        } else if line.starts_with("#ALBUM: ") {
            album = Some(line["#ALBUM: ".len()..].trim().to_string());
        } else if !line.starts_with('#') {
            lyrics.push(line.to_string());
        }
    }

    match (title, artist, path, genre, album) {
        (Some(t), Some(a), Some(p), Some(g), Some(alb)) => Some((t, a, p, g, alb, lyrics)),
        _ => None,
    }
}

pub fn search_lyrics(
    lyrics_dir: String,
    query: String,
    song_dir: String,
) -> anyhow::Result<Vec<SongMetadata>> {
    // Error handling cuz I just now realised the error it screams at me with is scary when no
    // lyrics dir exist
    let lyrics_path = Path::new(&lyrics_dir);
    if !lyrics_path.exists() || !lyrics_path.is_dir() {
        return Ok(Vec::new());
    }
    let query_lower = query.to_lowercase();

    // Build lookup maps
    let path_map: HashMap<String, SongMetadata> = scan_music_directory(song_dir, false)
        .into_iter()
        .map(|sm| (sm.path.clone(), sm))
        .collect();

    let mut title_artist_map: HashMap<(String, String, String, String), Vec<SongMetadata>> =
        HashMap::new();
    for sm in path_map.values() {
        title_artist_map
            .entry((
                sm.title.clone(),
                sm.artist.clone(),
                sm.genre.clone(),
                sm.album.clone(),
            ))
            .or_default()
            .push(sm.clone());
    }

    let path_map = Arc::new(path_map);
    let title_artist_map = Arc::new(title_artist_map);

    // Process LRC files in parallel
    let entries: Vec<_> = read_dir(lyrics_path)?.collect::<Result<Vec<_>, _>>()?;

    let results: Vec<SongMetadata> = entries
        .par_iter()
        .filter_map(|entry| {
            let path = entry.path();
            if path.extension().map(|e| e == "lrc").unwrap_or(false) {
                let content = fs::read_to_string(&path).ok()?;
                let (title, artist, lrc_path, genre, album, lyrics) = parse_lrc_metadata(&content)?;

                // Check if any lyric matches
                let has_match = lyrics
                    .iter()
                    .any(|line| line.to_lowercase().contains(&query_lower));

                if !has_match {
                    return None;
                }

                // Try to find matching metadata
                path_map.get(&lrc_path).cloned().or_else(|| {
                    title_artist_map
                        .get(&(title, artist, genre, album))
                        .and_then(|v| v.first().cloned())
                })
            } else {
                None
            }
        })
        .collect();

    // Deduplicate results
    let mut seen = HashSet::new();
    Ok(results
        .into_iter()
        .filter(|sm| seen.insert(sm.path.clone()))
        .collect())
}

pub fn preload_next_song(path: String) -> bool {
    if path.starts_with("cdda://") {
        return false;
    }
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        // Clear any existing preloaded track first
        *player.next_sink.lock().unwrap() = None;
        *player.next_buffer.lock().unwrap() = None;
        *player.next_path.lock().unwrap() = Some(path.clone());

        if let Ok(sender) = player.sender.lock() {
            sender.send(PlayerMessage::PreloadNext { path }).is_ok()
        } else {
            false
        }
    } else {
        false
    }
}

pub fn switch_to_preloaded_now() -> bool {
    if let Some(player) = PLAYER.lock().unwrap().as_ref() {
        if let Ok(sender) = player.sender.lock() {
            sender.send(PlayerMessage::SwitchToPreloaded).is_ok()
        } else {
            false
        }
    } else {
        false
    }
}
