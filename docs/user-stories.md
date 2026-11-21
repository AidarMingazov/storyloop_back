# User stories and sharing (wave 7)

Part 1 works without AI. Generation runs on a fake adapter, and the real pipeline plugs in after wave 6.

## Model

- A user story is a `Series` with `source: user` and `author`, plus its episode #1.
- Visibility (`private` / `link` / `public`) and `moderation_state` (`pending` / `approved` / `hidden`) live on the series.
- `share_token` (12 base58 characters), `origin_episode_id` (7.8) and the `reads_count` / `saves_count` / `shares_count` counters live on the episode.
- Catalog series keep the defaults (`public`, `approved`) and behave as before.
- `StoryRequest` is the generation brief: mode, theme, idea or text, pair, level, format, status and step. Limits count requests that did not fail.
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

## Seams for wave 6

| ENV | Today | Wave 6 |
|---|---|---|
| `STORY_GENERATOR` | `fake` → `Stories::FakeGenerator` | `pipeline` → `Ai::StoryPipeline` |
| `STORY_MODERATOR` | `fake` → `Stories::FakeModerator` | `pipeline` → `Ai::StoryModerator` |

- The generator contract is in `app/services/stories/generator.rb`: `call(story_request) → Episode`. The episode is filled into the series that already exists. The generator writes `GenerationLog`, calls `progress!(step)`, must be idempotent, and an exception means `failed`, which does not count against the limit.
- The moderator returns `check(text) → Stories::Verdict`. It runs on the idea or text before generation (`StoryForm`) and on the finished episode text (`GenerateStoryJob`).
- `GenerateStoryJob` runs on queue `stories` with priority 10, below catalog work.

Other settings: `FREE_STORY_GENERATIONS` (3), `STORY_REPORTS_TO_HIDE` (1: one open report takes the story out of the feed until an admin decides), `FAKE_STORY_STEP_DELAY` (1.5 s in dev).

## Events (PostHog)

| Event | When | Key properties |
|---|---|---|
| `story_created` | the brief is submitted | mode, theme, visibility, prompt_length, generations_left |
| `story_ready` / `story_failed` | the job finishes | seconds, cost_usd / rejected |
| `story_published` | the story becomes public (from the job or a visibility change) | listed |
| `story_shared` | "Share" is pressed | channel `web_share` / `copy` |
| `share_opened` | someone opens a shared link (`ref` or `utm_source=share`), not the author | ref, author, source, own, channel |
| `story_reported`, `author_hidden` | moderation by readers | reason, author |
| `paywall_viewed` / `checkout_clicked` with `reason: generation` | fake door after the free limit | |

Every event of a user who came through a link carries `ref`, the sharer's `public_id`. Their `signup` carries it too.

### K-factor in PostHog

K = (sign-ups from shares ÷ users who shared) × (users who shared ÷ active users), over the same period. In PostHog terms:

- invitations per user = `story_shared` (unique users) ÷ active users;
- conversion = `signup` where `ref` is set (unique users) ÷ `story_shared` (unique users);
- K = `signup` with `ref` ÷ active users. A trend insight with a formula over these two series is enough; a week works as the period.
