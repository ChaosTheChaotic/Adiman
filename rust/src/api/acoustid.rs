use crate::api::music_handler::SongMetadata;
use anyhow::Context;
use rodio::source::Source;
use rusty_chromaprint::{Configuration, Fingerprinter};
use serde::Deserialize;
use std::path::Path;

// The main lookup function
fn lookup_rs(path: impl AsRef<Path> + ToString) -> Option<SongMetadata> {
    let pref = path.as_ref();
    let f = match calc_fingerprint(pref) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("{e}");
            return None;
        }
    };
    let d = get_duration(pref);
    match lookup_metadata(f.as_slice(), d, path) {
        Ok(sm) => sm,
        Err(e) => {
            eprintln!("{e}");
            return None;
        }
    }
}

pub fn lookup(path: String) -> Option<SongMetadata> {
    lookup_rs(path)
}

fn calc_fingerprint(path: impl AsRef<Path>) -> anyhow::Result<Vec<u32>> {
    let path = path.as_ref();
    let src = std::fs::File::open(path).context("Failed to open file")?;
    let mss = symphonia::core::io::MediaSourceStream::new(Box::new(src), Default::default());

    let mut hint = symphonia::core::probe::Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let meta_opts: symphonia::core::meta::MetadataOptions = Default::default();
    let fmt_opts: symphonia::core::formats::FormatOptions = Default::default();

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &fmt_opts, &meta_opts)
        .context("Unsupported format")?;

    let mut fmt = probed.format;

    let track = fmt
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
        .context("No supported audio tracks")?;

    let dec_opts: symphonia::core::codecs::DecoderOptions = Default::default();

    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &dec_opts)
        .context("Unsupported codec")?;

    let tid = track.id;

    let mut printer = Fingerprinter::new(&Configuration::default());
    let srate = track
        .codec_params
        .sample_rate
        .context("Missing sample rate")?;
    let channels = track
        .codec_params
        .channels
        .context("Missing audio channels")?
        .count() as u32;
    printer
        .start(srate, channels)
        .context("Initializing fingerprinter")?;

    let mut sbuf = None;

    loop {
        let packet = match fmt.next_packet() {
            Ok(p) => p,
            Err(_) => break,
        };

        if packet.track_id() != tid {
            continue;
        }

        match decoder.decode(&packet) {
            Ok(abuf) => {
                if sbuf.is_none() {
                    let spec = *abuf.spec();
                    let dur = abuf.capacity() as u64;
                    sbuf = Some(symphonia::core::audio::SampleBuffer::<i16>::new(dur, spec));
                }

                if let Some(b) = &mut sbuf {
                    b.copy_interleaved_ref(abuf);
                    printer.consume(b.samples());
                }
            }
            Err(symphonia::core::errors::Error::DecodeError(_)) => (),
            Err(_) => break,
        }
    }
    printer.finish();
    Ok(printer.fingerprint().to_vec())
}

fn get_duration(path: impl AsRef<Path>) -> u64 {
    // Extract duration (fallback to 0 if decoding fails)
    if let Ok(file) = std::fs::File::open(path) {
        rodio::Decoder::try_from(file)
            .ok()
            .and_then(|source| source.total_duration().map(|d| d.as_secs()))
            .unwrap_or(0)
    } else {
        0
    }
}

#[derive(Debug, Deserialize, Clone)]
struct AcoustIdRecording {
    id: String,
    title: Option<String>,
    artists: Option<Vec<AcoustIdArtist>>,
    duration: Option<f64>,
    releasegroups: Option<Vec<AcoustIdReleaseGroup>>,
}

#[derive(Debug, Deserialize, Clone)]
struct AcoustIdArtist {
    id: String,
    name: String,
}

#[derive(Debug, Deserialize, Clone)]
struct AcoustIdReleaseGroup {
    id: String,
    title: String,
}

#[derive(Debug, Deserialize)]
struct AcoustIdResult {
    id: String,
    score: f64,
    recordings: Option<Vec<AcoustIdRecording>>,
}

#[derive(Debug, Deserialize)]
struct AcoustIdResponse {
    status: String,
    results: Vec<AcoustIdResult>,
}

fn lookup_metadata(
    fingerprint: &[u32],
    duration_secs: u64,
    path: impl AsRef<Path> + ToString,
) -> anyhow::Result<Option<SongMetadata>> {
    let client_key =
        std::env::var("ACOUSTID_API").context("ACOUSTID_API environment variable not set")?;

    // Convert fingerprint to the string format AcoustID expects
    let fingerprint_string = fingerprint
        .iter()
        .map(|x| x.to_string())
        .collect::<Vec<_>>()
        .join(",");

    let client: reqwest::blocking::Client = reqwest::blocking::Client::new();
    let response = client
        .get("https://api.acoustid.org/v2/lookup")
        .query(&[
            ("client", &client_key),
            ("duration", &duration_secs.to_string()),
            ("fingerprint", &fingerprint_string),
            ("meta", &"recordings+releasegroups+compress".to_string()),
        ])
        .send()
        .context("Failed to send request to AcoustID")?;

    let acoustid_response: AcoustIdResponse = response
        .json()
        .context("Failed to parse AcoustID response")?;

    // Extract the best match (highest score)
    let best_result = acoustid_response
        .results
        .into_iter()
        .max_by(|a, b| a.score.partial_cmp(&b.score).unwrap());

    let Some(result) = best_result else {
        return Ok(None);
    };

    let Some(recordings) = result.recordings else {
        return Ok(None);
    };

    // Take the first recording with available data
    let recording = recordings
        .clone()
        .into_iter()
        .find(|rec| rec.title.is_some() && rec.artists.is_some())
        .or_else(|| recordings.into_iter().next());

    let Some(recording) = recording else {
        return Ok(None);
    };

    let artist = recording
        .artists
        .and_then(|artists| artists.into_iter().next())
        .map(|artist| artist.name)
        .unwrap_or_else(|| "Unknown Artist".to_string());

    let album = recording
        .releasegroups
        .and_then(|groups| groups.into_iter().next())
        .map(|group| group.title)
        .unwrap_or_else(|| "Unknown Album".to_string());

    Ok(Some(SongMetadata {
        title: recording
            .title
            .unwrap_or_else(|| "Unknown Title".to_string()),
        artist,
        album,
        duration: recording
            .duration
            .map(|d| d as u64)
            .unwrap_or(duration_secs),
        path: path.to_string(),
        // Following 2 fields are never provided
        album_art: None,
        genre: "Unknown genre".to_string(),
    }))
}
