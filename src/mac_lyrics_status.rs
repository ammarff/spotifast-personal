//! The optional lyric line beside Spotifast's existing menu-bar icon.

use std::cell::RefCell;

use objc2::rc::Retained;
use objc2_app_kit::{NSStatusBar, NSStatusItem};
use objc2_foundation::{MainThreadMarker, NSString};

struct Status {
    item: Retained<NSStatusItem>,
    text: String,
    visible: bool,
}

thread_local! {
    static STATUS: RefCell<Option<Status>> = const { RefCell::new(None) };
}

/// AppKit status items live on the main thread. Hidden or absent lyrics leave
/// the existing tray icon alone and take no menu-bar space.
pub fn sync(enabled: bool, lyric: Option<&str>) {
    let Some(mtm) = MainThreadMarker::new() else {
        return;
    };
    STATUS.with(|cell| {
        let mut state = cell.borrow_mut();
        if !enabled || lyric.is_none_or(|line| line.trim().is_empty()) {
            if let Some(status) = state.as_mut()
                && status.visible
            {
                status.item.setVisible(false);
                status.visible = false;
            }
            return;
        }
        let status = state.get_or_insert_with(|| Status {
            item: NSStatusBar::systemStatusBar().statusItemWithLength(-1.0),
            text: String::new(),
            visible: false,
        });
        let line = lyric.expect("checked above");
        let clean: String = line
            .chars()
            .map(|character| {
                if character.is_whitespace() {
                    ' '
                } else {
                    character
                }
            })
            .collect();
        if status.text != clean {
            let label = shorten(&clean, 48);
            if let Some(button) = status.item.button(mtm) {
                button.setTitle(&NSString::from_str(&label));
                button.setToolTip(Some(&NSString::from_str(&clean)));
            }
            status.text = clean;
        }
        if !status.visible {
            status.item.setVisible(true);
            status.visible = true;
        }
    });
}

fn shorten(text: &str, max_chars: usize) -> String {
    let mut chars = text.chars();
    let head: String = chars.by_ref().take(max_chars).collect();
    if chars.next().is_some() {
        format!("{head}…")
    } else {
        head
    }
}

#[cfg(test)]
mod tests {
    use super::shorten;

    #[test]
    fn menu_bar_text_is_bounded_by_characters() {
        assert_eq!(shorten("aé🙂", 2), "aé…");
        assert_eq!(shorten("aé", 2), "aé");
    }
}
