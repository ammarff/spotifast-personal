//! The optional lyric line beside Spotifast's existing menu-bar icon.

use std::ffi::CString;

unsafe extern "C" {
    fn spotifast_menu_lyrics_sync(
        enabled: std::ffi::c_int,
        line: *const std::ffi::c_char,
        reduced_motion: std::ffi::c_int,
    );
}

/// AppKit owns the bounded status item and scrolls a long line on its main
/// run loop, including when the Spotifast window is hidden.
pub fn sync(enabled: bool, line: Option<&str>, reduced_motion: bool) {
    let text = line
        .filter(|line| !line.trim().is_empty())
        .and_then(|line| CString::new(line).ok());
    // SAFETY: Application frames run on AppKit's main thread. The bridge
    // copies the UTF-8 line into an NSString before this CString is dropped.
    unsafe {
        spotifast_menu_lyrics_sync(
            i32::from(enabled),
            text.as_ref().map_or(std::ptr::null(), |line| line.as_ptr()),
            i32::from(reduced_motion),
        );
    }
}

#[cfg(test)]
mod tests {
    unsafe extern "C" {
        fn spotifast_marquee_offset(
            overflow: f64,
            viewport: f64,
            elapsed: f64,
            reduced_motion: std::ffi::c_int,
        ) -> f64;
    }

    fn offset(overflow: f64, viewport: f64, elapsed: f64, reduced: bool) -> f64 {
        // SAFETY: The function is pure arithmetic over four scalar inputs.
        unsafe { spotifast_marquee_offset(overflow, viewport, elapsed, i32::from(reduced)) }
    }

    #[test]
    fn long_lines_pause_then_reach_the_end_without_an_ellipsis() {
        assert_eq!(offset(120.0, 220.0, 0.4, false), 0.0);
        assert_eq!(offset(120.0, 220.0, 1.8, false), 60.0);
        assert_eq!(offset(120.0, 220.0, 3.2, false), 120.0);
        assert_eq!(offset(0.0, 220.0, 9.0, false), 0.0);
    }

    #[test]
    fn reduced_motion_pages_through_the_full_line() {
        assert_eq!(offset(400.0, 220.0, 0.0, true), 0.0);
        assert_eq!(offset(400.0, 220.0, 2.5, true), 200.0);
        assert_eq!(offset(400.0, 220.0, 5.0, true), 400.0);
        assert_eq!(offset(400.0, 220.0, 7.5, true), 0.0);
    }
}
