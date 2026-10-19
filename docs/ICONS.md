# Icon guide

How Luis Sejer's app icons are drawn, so they read as one family: the Topside apps, the luissejer.dk icon, Snicker and Agent Orrery.

**In short:** a rich colour gradient carries each app's identity; one bold, simple object sits on it with real depth (a specular rim, a shadow in the ground's colour); one accent detail; nothing else.

Why: the first Topside icons were illustrations (many parts, realistic objects, competing light) and looked cheap. The second set followed Agent Orrery's light-ground, line-drawn style and lost their character: beige grounds and thin lines all look alike in the Dock. Premium Mac icons since Big Sur, and the Liquid Glass ones in macOS 26, are colourful and layered: a gradient background layer, one or two simple foreground layers with depth, specular highlights and shadows lit from above. Snicker's icon is the model: a vivid gradient, one white card, one word.

**Agent Orrery is the one exception:** the light ground with dashed orbits is its signature, and it stays the family's gem.

## The canvas

- **1024 × 1024**, transparent. The body is the macOS grid: `<rect x="100" y="100" width="824" height="824" rx="185">`. Drawing outside it gets the icon put in a gray frame by macOS 26.
- **A glass rim** on the body: a 2 px inner stroke, white at about 35% along the top fading to about 5% at the bottom, so the edge catches the light like Liquid Glass.
- **No shadow under the body in the art.** It's added when rendering, as two drop shadows tinted with the ground's deep colour, never black: `drop-shadow(0 22px 34px <deep>/30%) drop-shadow(0 3px 6px <deep>/18%)`.

## The ground: colour is the identity

- **A tonal gradient in the app's own hue,** diagonal from the top left to the bottom right, between two stops about 15–25° apart on the colour wheel: lighter and slightly warmer at the top, deeper at the bottom. Snicker's runs warm orange to magenta. Each app owns a hue so the Dock reads as a spectrum.
- **Light from above:** a soft radial white glow at the top centre (about 25% at its brightest) and a gentle darkening along the bottom edge.
- Saturated, never neon. No flat fills, no rainbow (two neighbouring hues only), no textures, photos or patterns.

## The object: one bold idea

- **One simple object, centred,** taking about 55–65% of the body's width. It says what the app does in one shape you could draw from memory: a page, a cup, a drop, a ring, a link. No scenes, hands, faces or perspective.
- **Solid, not line art.** Filled shapes carry the icon; strokes, if any, are bold (at least 40 px at 1024) and secondary. Thin outlines look weak at Dock size.
- **Material:** porcelain white by default, a gradient from white at the top to a pale tint of the ground's hue at the bottom, or frosted glass that lets the ground's colour through. A 1–2 px specular highlight runs along its top edges.
- **A shadow in the ground's colour,** soft and slightly below, so the object floats on the ground: `drop-shadow(0 18px 28px <deep>/45%)`.
- **One accent detail** may use a second colour: the ground's deepest shade, or one complementary pop (Snicker's word "GIF" in the ground's magenta). Exactly one.
- **Gloss only where light would really catch:** rims, top edges and spheres. Spheres get a radial gradient lit from the top left (`cx="0.35" cy="0.3" r="0.75"`). No bevels, chrome or glassy blobs.
- **Draw it on a 32-unit grid** (32 px a unit at 1024), so it simplifies to the app's menu bar glyph and still reads at 16 px.
- **Text** appears only when the name is the mark (SEJER, GIF), in solid blocks or one bold word.

## Check before shipping

1. Render at 1024 and look at it at **64, 32 and 16 px**. At 16 px the silhouette and the accent should still say which app it is.
2. Put it in a row with Snicker, Orrery and the rest at Dock size. Does it have its own colour and silhouette? If it looks busier or shinier than Snicker, take something away. If it looks flatter or paler, it has lost its character.
3. One hue family on the ground? One bold object, solid rather than outlined? One accent? Specular rim? Shadows in the ground's colour, not black?

## The palettes

Each icon's colours, so the family stays apart and in tune round the colour wheel: in Dock order the grounds run red, orange, gold, lime, green, teal, sky, blue, violet, rose, then graphite for Drawer. The full shades (the deep shadow colour and the porcelain's tint) are in `docs/src/icons.html` (Topside) and in the apps site's `art/sejer-icon.html` (luissejer.dk). Add a row when you add an icon.

| Icon | Ground top | Ground bottom | Object | Accent |
|---|---|---|---|---|
| Agent Orrery | `#ffffff` | `#e7eeea` | dark sphere, dashed orbits | `#34955f` moon |
| Week | `#ff6f5c` | `#e0253f` | porcelain calendar page on binder rings | `#e3283f` this week's row |
| Awake | `#ffbf57` | `#f26f1f` | porcelain coffee cup | `#6e3612` coffee |
| Pipette | `#ffe169` | `#f4a21f` | porcelain eyedropper | `#7a45e6` the picked drop |
| Mirror | `#c2ea6a` | `#5bb43a` | porcelain hand mirror, pale glass | `#4f9a2a` you in the glass |
| Upnext | `#4ddfa4` | `#10a37a` | porcelain ring | `#ff8a2a` the countdown |
| Shelf | `#43d8d2` | `#0d96a8` | porcelain tray and two files | `#ff7a59` photo on the front file |
| Scrub | `#5fc9ff` | `#178de0` | two interlocked porcelain links | `#ffc93a` polish sparkle |
| Zones | `#7393ff` | `#3a4be0` | porcelain globe | `#2535b4` clock hands |
| Beam | `#d98dff` | `#9a3ce0` | tilted porcelain QR card | `#6a26aa` finder squares |
| Hush | `#ff7fa9` | `#e5306c` | porcelain microphone, cut by the slash | `#a5124a` the slash |
| Drawer | `#717986` | `#2d323b` | porcelain menu bar strip, icons fading behind the divider | `#5fb4ff` the chevron |
| luissejer.dk (SEJER) | `#e6493a` | `#9c1a17` | tilted paper card, SEJER in `#141414` blocks | `#c8281c` the S's top block |
