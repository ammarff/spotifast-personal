//! Native Touch Bar lyrics. The Objective-C bridge keeps unsupported macOS
//! presentation calls isolated from the rest of Spotifast.

use std::ffi::CString;

unsafe extern "C" {
    fn spotifast_touch_bar_sync(enabled: std::ffi::c_int, line: *const std::ffi::c_char);
}

/// Called on AppKit's main thread after each application frame.
pub fn sync(enabled: bool, line: Option<&str>) {
    let text = line
        .filter(|line| !line.trim().is_empty())
        .and_then(|line| CString::new(line).ok());
    // SAFETY: App frames run on the main thread, and the bridge copies the
    // UTF-8 string into an NSString before this CString is dropped.
    unsafe {
        spotifast_touch_bar_sync(
            i32::from(enabled),
            text.as_ref().map_or(std::ptr::null(), |line| line.as_ptr()),
        );
    }
}
