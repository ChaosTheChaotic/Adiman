use anyhow::Context;
use rusty_chromaprint::{Configuration, Fingerprinter};
use std::path::Path;

pub fn calc_fingerprint(path: impl AsRef<Path>) -> anyhow::Result<Vec<u32>> {
    let path = path.as_ref();
    let src = std::fs::File::open(path).context("Failed to open file")?;
    let mss = symphonia::core::io::MediaSourceStream::new(Box::new(src), Default::default());

    let mut hint = symphonia::core::probe::Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let meta_opts: symphonia::core::meta::MetadataOptions = Default::default();
    let fmt_opts: symphonia::core::formats::FormatOptions = Default::default();
    
    let probed = symphonia::default::get_probe().format(&hint, mss, &fmt_opts, &meta_opts).context("Unsupported format")?;

    let mut fmt = probed.format;

    let track = fmt.tracks().iter().find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL).context("No supported audio tracks")?;

    let dec_opts: symphonia::core::codecs::DecoderOptions = Default::default();

    let mut decoder = symphonia::default::get_codecs().make(&track.codec_params, &dec_opts).context("Unsupported codec")?;

    let tid = track.id;

    let mut printer = Fingerprinter::new(&Configuration::default());
    let srate = track.codec_params.sample_rate.context("Missing sample rate")?;
    let channels = track.codec_params.channels.context("Missing audio channels")?.count() as u32;
    printer.start(srate, channels).context("Initializing fingerprinter")?;

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
