use image::{GenericImageView, Pixel};
use std::collections::HashMap;

// Constants for color processing
const RESIZE_TARGET: u32 = 112; // Reduced size for processing
const QUANTIZE_BITS: u8 = 5; // Number of bits per channel for quantization

#[derive(Debug)]
struct ColorScore {
    color: u32,
    score: f32,
    count: u32,
}

pub fn get_dominant_color(data: Vec<u8>) -> Option<u32> {
    // Decode base64 and load image
    let img = image::load_from_memory(&data).ok()?;

    // Resize for faster processing while maintaining enough detail
    let small_img = img.resize_exact(
        RESIZE_TARGET,
        RESIZE_TARGET,
        image::imageops::FilterType::Triangle,
    );

    let mut color_scores = HashMap::new();

    // Process each pixel
    for pixel in small_img.pixels() {
        let rgb = pixel.2.to_rgb();

        // Convert to HSL for filtering
        let (_, s, l) = rgb_to_hsl(rgb[0], rgb[1], rgb[2]);

        // Quantize color
        let key = quantize_color(rgb[0], rgb[1], rgb[2]);
        let entry = color_scores.entry(key).or_insert(ColorScore {
            color: rgb_to_argb(rgb[0], rgb[1], rgb[2]),
            score: calculate_color_score(s, l),
            count: 0,
        });
        entry.count += 1;
    }

    // Find the dominant color based on frequency and score
    color_scores
        .values()
        .max_by(|a, b| {
            let a_weight = a.count as f32 * a.score;
            let b_weight = b.count as f32 * b.score;
            a_weight.partial_cmp(&b_weight).unwrap()
        })
        .map(|score| score.color)
        .or(Some(0xFF383770)) // Default color if no dominant color found
}

fn quantize_color(r: u8, g: u8, b: u8) -> u32 {
    let r = (r as u32 >> (8 - QUANTIZE_BITS)) << (QUANTIZE_BITS * 2);
    let g = (g as u32 >> (8 - QUANTIZE_BITS)) << QUANTIZE_BITS;
    let b = b as u32 >> (8 - QUANTIZE_BITS);
    r | g | b
}

fn rgb_to_argb(r: u8, g: u8, b: u8) -> u32 {
    0xFF000000 | ((r as u32) << 16) | ((g as u32) << 8) | (b as u32)
}

fn rgb_to_hsl(r: u8, g: u8, b: u8) -> (f32, f32, f32) {
    let r = r as f32 / 255.0;
    let g = g as f32 / 255.0;
    let b = b as f32 / 255.0;

    let max = r.max(g.max(b));
    let min = r.min(g.min(b));
    let delta = max - min;

    let l = (max + min) / 2.0;

    let s = if delta == 0.0 {
        0.0
    } else {
        delta / (1.0 - (2.0 * l - 1.0).abs())
    };

    let h = if delta == 0.0 {
        0.0
    } else if max == r {
        60.0 * (((g - b) / delta) % 6.0)
    } else if max == g {
        60.0 * ((b - r) / delta + 2.0)
    } else {
        60.0 * ((r - g) / delta + 4.0)
    };

    (h, s, l)
}

fn calculate_color_score(saturation: f32, luminance: f32) -> f32 {
    // Score based on saturation and luminance
    // Prefer moderately saturated colors with medium luminance
    let sat_score = 1.0 - (saturation - 0.5).abs() * 2.0;
    let lum_score = 1.0 - (luminance - 0.5).abs() * 2.0;
    sat_score * lum_score
}
