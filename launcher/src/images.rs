//! Pictures of the news cards (O552). A picture comes from the feed (`image`, an https address), is fetched with a size
//! limit and decoded here, on a thread of its own. Anything wrong (too big, not PNG or JPEG, odd size) is `None` and the
//! card shows the default art of its tag. Decoding runs only on the bytes that passed `MAX_BYTES`, and the decoder is
//! given the picture's size limits before it allocates.
use crate::net::Fetch;
use image::ImageReader;
use std::io::Cursor;

/// A picture file bigger than this is not fetched.
pub const MAX_BYTES: u64 = 400 * 1024;
pub const MAX_W: u32 = 2000;
pub const MAX_H: u32 = 1000;
pub const FETCH_SECS: u32 = 10;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rgba {
    pub w: usize,
    pub h: usize,
    pub rgba: Vec<u8>,
}

/// PNG or JPEG bytes to raw RGBA. None for any other format, a picture over `MAX_W` x `MAX_H`, or a broken file.
pub fn decode(bytes: &[u8]) -> Option<Rgba> {
    if bytes.is_empty() || bytes.len() as u64 > MAX_BYTES {
        return None;
    }
    let mut reader = ImageReader::new(Cursor::new(bytes)).with_guessed_format().ok()?;
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(MAX_W);
    limits.max_image_height = Some(MAX_H);
    limits.max_alloc = Some(32 * 1024 * 1024);
    reader.limits(limits);
    match reader.format()? {
        image::ImageFormat::Png | image::ImageFormat::Jpeg => {}
        _ => return None,
    }
    let im = reader.decode().ok()?.to_rgba8();
    let (w, h) = (im.width() as usize, im.height() as usize);
    (w >= 16 && h >= 16).then(|| Rgba {
        w,
        h,
        rgba: im.into_raw(),
    })
}

/// Fetches and decodes one picture; any failure is None.
pub fn load(fetch: &dyn Fetch, url: &str) -> Option<Rgba> {
    let bytes = fetch.get_small(url, FETCH_SECS, MAX_BYTES).ok()?;
    decode(&bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn png(w: u32, h: u32) -> Vec<u8> {
        let img = image::RgbaImage::from_pixel(w, h, image::Rgba([200, 80, 20, 255]));
        let mut out = Vec::new();
        img.write_to(&mut Cursor::new(&mut out), image::ImageFormat::Png)
            .unwrap();
        out
    }

    #[test]
    fn a_png_decodes() {
        let r = decode(&png(40, 20)).unwrap();
        assert_eq!((r.w, r.h, r.rgba.len()), (40, 20, 40 * 20 * 4));
        assert_eq!(&r.rgba[..4], &[200, 80, 20, 255]);
    }

    #[test]
    fn the_shipped_default_art_decodes() {
        for n in ["update", "news", "event", "notice"] {
            let b = std::fs::read(format!("assets/news_{n}.jpg")).unwrap();
            let r = decode(&b).unwrap();
            assert_eq!((r.w, r.h), (560, 140), "{n}");
        }
    }

    #[test]
    fn refuses_what_it_should() {
        assert!(decode(b"").is_none());
        assert!(decode(b"not a picture at all").is_none());
        assert!(decode(&png(2001, 10)).is_none(), "too wide");
        assert!(decode(&png(10, 1001)).is_none(), "too tall");
        assert!(decode(&png(4, 4)).is_none(), "too small to be a card picture");
        // a GIF header is not a format we take
        assert!(decode(b"GIF89a\x10\x00\x10\x00\x00\x00\x00;").is_none());
        // a file over the byte limit is refused before decoding
        let mut big = png(40, 20);
        big.resize(MAX_BYTES as usize + 1, 0);
        assert!(decode(&big).is_none());
        // a cut file
        let p = png(40, 20);
        assert!(decode(&p[..p.len() / 2]).is_none());
    }
}
