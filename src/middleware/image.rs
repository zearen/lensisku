use image::imageops::FilterType;
use image::DynamicImage;
use image::GenericImageView;
use webp::Encoder;

const MAX_DIMENSION: u32 = 256;
const WEBP_QUALITY: f32 = 75.0; // Good balance for avatars
const WEBP_TARGET_SIZE: usize = 20 * 1024; // Target 20KB for avatars

pub struct ImageProcessor;

impl ImageProcessor {
    pub fn compress_avatar(data: &[u8], _mime_type: &str) -> Result<(Vec<u8>, String), String> {
        // Load image
        let img =
            image::load_from_memory(data).map_err(|e| format!("Failed to load image: {}", e))?;

        // Resize maintaining aspect ratio
        let resized = Self::resize_maintain_aspect(&img);

        // Convert to WebP with optimized settings
        let rgba = resized.to_rgba8();
        let width = rgba.width();
        let height = rgba.height();

        let encoder = Encoder::from_rgba(&rgba, width, height);
        let mut webp = encoder.encode(WEBP_QUALITY);

        // If resulting WebP is too large, gradually reduce quality until we meet target size
        let mut current_quality = WEBP_QUALITY;
        while webp.len() > WEBP_TARGET_SIZE && current_quality > 30.0 {
            current_quality -= 5.0;
            let encoder = Encoder::from_rgba(&rgba, width, height);
            webp = encoder.encode(current_quality);
        }

        Ok((webp.to_vec(), "image/webp".to_string()))
    }

    fn resize_maintain_aspect(img: &DynamicImage) -> DynamicImage {
        let (width, height) = img.dimensions();

        if width <= MAX_DIMENSION && height <= MAX_DIMENSION {
            return img.clone();
        }

        let ratio = width as f32 / height as f32;
        let (new_width, new_height) = if width > height {
            (MAX_DIMENSION, (MAX_DIMENSION as f32 / ratio) as u32)
        } else {
            ((MAX_DIMENSION as f32 * ratio) as u32, MAX_DIMENSION)
        };

        img.resize_exact(new_width, new_height, FilterType::Lanczos3)
    }
}
