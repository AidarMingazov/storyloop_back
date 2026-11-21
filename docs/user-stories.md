# User stories and sharing (wave 7)

Part 1 (model, links, moderation by readers, feed, limits) works without AI. Part 2 runs the stories on the wave 6
pipeline: casts, AI moderation, story by voice, comics from photos and translation into another pair. Development and
tests use fakes (`STORY_GENERATOR=fake`, `STORY_MODERATOR=fake`); production uses the AI by default.

## Model

- A user story is a `Series` with `source: user` and `author`, plus its episode #1.
- Visibility (`private` / `link` / `public`) and `moderation_state` (`pending` / `approved` / `hidden`) live on the series.
- `share_token` (12 base58 characters), `origin_episode_id` (7.8) and the `reads_count` / `saves_count` / `shares_count` counters live on the episode.
- Catalog series keep the defaults (`public`, `approved`) and behave as before.
- `StoryRequest` is the generation brief: mode (`theme` / `idea` / `text` / `surprise` / `photos`), theme, idea or text, cast, pair, level, format, status and step, `rejection` (the rule moderation stopped it for), and for photos the photos themselves, `vision`, `confirmed_at` and `redraws`. Limits count requests that did not fail.
- `TranslationRequest` is a reader's vote for a translation into another pair (7.8).
- `Report` holds a complaint and `AuthorBlock` holds "hide author". `users` get `public_id` (author page and `ref`), `display_name`, `banned_at` and `referrer_id`.

## Who can read what: `StoryAccess`

One rule covers the reader (`/episodes/:id` and `/s/:share_token`), reading progress and shares:

| Case | Who can read |
|---|---|
| catalog | published episodes, as before; the paywall decides what is free |
| author | always, even while generating, after a failure or when hidden |
| `hidden` story or banned author | nobody else |
| `public` | everyone |
| `link` | only through `/s/:share_token` |
| `private` | only the author |

The feed and the author page show only `Series.listed` stories: public, approved, published, and the author is not banned. Authors the reader hid and stories the reader reported are left out too.

Links to user stories always go through `/s/:token` (`read_path`). Messenger crawlers get a light page with OG tags only (`LinkPreview`), so no guest is created and no events fire.

JSON API v1 follows the same rule: `GET /api/v1/episodes/:id` and `GET /api/v1/s/:share_token` answer 404 for a story the client may not read, and new progress needs access too (docs/api.md).

## Generation (7.4)

| ENV | `fake` | `pipeline` (production default) |
|---|---|---|
| `STORY_GENERATOR` | `Stories::FakeGenerator`: a seed episode, placeholder art, no AI | `Stories::PipelineGenerator`: the wave 6 pipeline |
| `STORY_MODERATOR` | `Stories::FakeModerator`: rejects the marker `[[blocked]]` | `Stories::AiModerator`: a JSON verdict from a cheap model |

- The contract is in `app/services/stories/generator.rb`: `call(story_request) → Episode` (plus `cast_from_photos` and `redraw_sheet` for photos). The episode is filled into the series that already exists; the generator writes `GenerationLog`, calls `progress!(step)`, must be safe to run again, and an exception means `failed`, which does not count against the limit.
- **Casts** (`db/templates/ai/casts/*.yml`, README there): characters with sheets, art style and voices per target language. One per theme card plus "classic"; `cafe` is the default for an idea or own text, "surprise me" takes a random one, and the form lets the author pick. `Stories::Cast#cast_into` copies a cast into the story's series; every copy attaches the same sheet blob. `bin/rails stories:casts:check` lists missing sheets, `stories:casts:sheets` draws them (~$0.04 each), `stories:casts:upload` uploads them (form previews).
- **`Stories::Script`** is the wave 6 scenario step with `db/templates/ai/prompts/story.md.erb`: one complete episode (6 panels for a comic, 3 parts for a chat), from a theme, an idea, the learner's own text (adapted, not reinvented) or "surprise me" (avoids the author's earlier stories). Names from the brief are mapped onto the cast (`"cast": {"<key>": "<name>"}`).
- Then images (a failed panel is drawn once more, a panel the provider refuses rejects the story), layout, tokens, audio; the episode is published. A story costs about $0.30 (comic) or $0.05 (chat).
- `GenerateStoryJob` runs on queue `stories` with priority 10, below catalog work.

## Moderation (7.6)

- The brief is checked in `GenerateStoryJob` before anything is generated, the finished story before it goes out (`db/templates/ai/prompts/moderation.md.erb`, config step `moderation`: Haiku, DeepSeek as fallback). No verdict after retries fails the story: nothing unchecked is published.
- A rejection stores its category (`Stories::REJECTIONS`: sexual, violence, hate, self_harm, personal, copyright, illegal, minors, images, other); the status page names it and says the attempt did not count.
- Readers still report and hide authors (part 1); the admin queue decides.

## Story by voice (7.12)

"Dictate" on the idea field records 16 kHz mono WAV in the browser (`voice_input_controller.js`, up to 90 s) and posts it to `POST /stories/transcription`. `Ai::Stt::LlmAudio` sends it as `input_audio` to Gemini Flash on OpenRouter (config step `stt`, provider `openrouter_audio` with the openrouter key); the text lands in the field for editing. Signed-in authors only, 10 per minute, logged as step `stt`.

## Comic from photos (7.11)

1. The form takes 1–10 JPEG/PNG/WebP photos (≤ 10 MB), an optional wish for the plot and consent (own photos, people agree, no children). Private by default, always a comic.
2. `Stories::PhotoCast`: a vision model (step `vision`, `prompts/photos.md.erb`) gets the photos downscaled to 1600 px and stripped of EXIF. Children, nudity, violence or a famous person reject the story. Up to 3 people or animals become characters `p1..p3`; `Stories::PhotoSheet` draws each sheet after their clearest photo (step `photo_sheets`, Seedream 5.0 lite, "not photorealistic"). The chosen cast gives the art style, the photo places become the settings. Without people or animals the cast's characters play there.
3. The request waits (`confirming`): the author sets names (Latin letters) and voices, may redraw sheets (5 per story, `RedrawStorySheetJob`) and confirms; then the story is written around the photo scenes.
4. The photos are deleted when the request ends; unconfirmed requests fail after 7 days (`ExpireStoryConfirmationsJob`, daily) and their photos go too.

Not done: photo places as reference images for the backgrounds (they are described in the style prompt only).

## Translation into another pair (7.8)

- `Stories::Translation` copies an episode into another pair with `origin_episode`: the same pictures (shared blobs) and characters; the model retells every bubble in the new target language at the episode's level (`prompts/translate.md.erb`, panel and bubble structure kept), then layout, tokens and audio run again (~$0.07).
- Admin: "Translate into …" on the episode page (`TranslateEpisodeJob`). A user story becomes the same author's story with the same visibility, published after moderation; a catalog episode goes into the series of the same slug in the other pair, for review.
- Readers: "I want this story in …" under a user story — one vote per reader (`translation_requested`), counted on the admin pages; once the translation is published, the button opens it.

## Settings

`FREE_STORY_GENERATIONS` (3), `STORY_REPORTS_TO_HIDE` (1: one open report takes the story out of the feed until an admin decides), `FAKE_STORY_STEP_DELAY` (1.5 s in dev). AI providers and models: `config/ai.yml` steps `script`, `images`, `tokens`, `audio`, `moderation`, `vision`, `photo_sheets`, `sheets`, `stt`.

## Events (PostHog)

| Event | When | Key properties |
|---|---|---|
| `story_created` | the brief is submitted | mode, theme, visibility, prompt_length, generations_left |
| `story_ready` / `story_failed` | the job finishes | seconds, cost_usd / rejected, category |
| `story_published` | the story becomes public (from the job or a visibility change) | listed |
| `story_shared` | "Share" is pressed | channel `web_share` / `copy` |
| `share_opened` | someone opens a shared link (`ref` or `utm_source=share`), not the author | ref, author, source, own, channel |
| `story_reported`, `author_hidden` | moderation by readers | reason, author |
| `translation_requested` | "I want this story in …" | pair |
| `paywall_viewed` / `checkout_clicked` with `reason: generation` | fake door after the free limit | |

Every event of a user who came through a link carries `ref`, the sharer's `public_id`. Their `signup` carries it too.

### K-factor in PostHog

K = (sign-ups from shares ÷ users who shared) × (users who shared ÷ active users), over the same period. In PostHog terms:

- invitations per user = `story_shared` (unique users) ÷ active users;
- conversion = `signup` where `ref` is set (unique users) ÷ `story_shared` (unique users);
- K = `signup` with `ref` ÷ active users. A trend insight with a formula over these two series is enough; a week works as the period.
