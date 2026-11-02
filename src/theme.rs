use ratatui::style::Color;

#[derive(Clone, Copy, Debug)]
pub struct Palette {
    pub background: Color,
    pub surface: Color,
    pub border: Color,
    pub text: Color,
    pub muted: Color,
    pub pink: Color,
    pub cyan: Color,
    pub green: Color,
    pub yellow: Color,
    pub red: Color,
}

fn rgb(hex: u32) -> Color {
    Color::Rgb(((hex >> 16) & 255) as u8, ((hex >> 8) & 255) as u8, (hex & 255) as u8)
}

pub const THEMES: &[&str] = &["arctic", "blossom", "midnight", "oled", "mint"];

pub fn palette(theme: &str) -> Palette {
    match theme {
        "blossom" => Palette {
            background: rgb(0x211B2B), surface: rgb(0x30253C), border: rgb(0x60405B),
            text: rgb(0xFFF0F7), muted: rgb(0xB99AB4), pink: rgb(0xFF96C5),
            cyan: rgb(0xC3B9FF), green: rgb(0xB4E5C7), yellow: rgb(0xFFE1AE),
            red: rgb(0xFF8B9A),
        },
        "midnight" => Palette {
            background: rgb(0x0B101C), surface: rgb(0x161F30), border: rgb(0x34425F),
            text: rgb(0xDFE7FB), muted: rgb(0x8290AF), pink: rgb(0xC8AEFF),
            cyan: rgb(0x83CCFF), green: rgb(0x9FDFCF), yellow: rgb(0xF8D5A4),
            red: rgb(0xFF91AF),
        },
        "oled" => Palette {
            background: rgb(0x050608), surface: rgb(0x13131A), border: rgb(0x343442),
            text: rgb(0xF9F4FB), muted: rgb(0x94919F), pink: rgb(0xFFB9DA),
            cyan: rgb(0xA7EAFF), green: rgb(0xACF0CE), yellow: rgb(0xFFDAAA),
            red: rgb(0xFF8EA8),
        },
        "mint" => Palette {
            background: rgb(0x14212A), surface: rgb(0x203541), border: rgb(0x3A6664),
            text: rgb(0xE3F5EE), muted: rgb(0x90B8B4), pink: rgb(0xF5B5D4),
            cyan: rgb(0x8FE3E2), green: rgb(0x96F5C5), yellow: rgb(0xF6DFA9),
            red: rgb(0xF4A0B1),
        },
        _ => Palette {
            background: rgb(0x1C1E2D), surface: rgb(0x282A3F), border: rgb(0x50546C),
            text: rgb(0xE6E9F5), muted: rgb(0x9CA5BE), pink: rgb(0xF3AACB),
            cyan: rgb(0x9BDDE9), green: rgb(0xA6DEBF), yellow: rgb(0xF2D49E),
            red: rgb(0xFFA1B5),
        },
    }
}

pub fn validate(theme: &str) -> bool {
    THEMES.contains(&theme)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn builtin_palettes_exist() {
        for theme in THEMES {
            assert!(validate(theme));
            let palette = palette(theme);
            assert_ne!(palette.background, palette.text);
        }
    }
}
