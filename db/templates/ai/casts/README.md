# Casts for user stories (wave 7.4)

A cast is the characters and art style a user story is drawn with: the story's series gets a copy of them
(`Stories::Cast#cast_into`), so the pipeline works exactly as for catalog series.

- `title` — card label on "Create a story" (ru / en).
- `themes` — theme cards (`Stories::Themes`) that use this cast; `cafe` is the default for an idea or own text.
- `art_style` / `style_prompt` / `tone` — as in series templates (`../series/*.yml`).
- `names` / `voice` / `narrator_voice` — per target language (`ko`, `en`): Korean stories use the `ko` name and voice.
- `sheet` — path under `db/templates/ai/`; casts reuse the sheets of series templates where they fit.
  Missing sheets: `bin/rails stories:casts:sheets` (Seedream, ~$0.04 each) writes `casts/<cast>/<character>.jpeg`.
- `speech_level` — Korean only, as in series templates.
