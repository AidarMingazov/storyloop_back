# Storyloop JSON API v1

For native clients (a separate app; Hotwire Native uses the web pages directly). The episode JSON is
the same one the web reader renders, so every client draws from one format.

Base URL: `https://<host>/api/v1`. Requests and responses are JSON.

## Auth

Every call except creating a guest or a session sends `Authorization: Bearer <token>`.

| Call | Body | Response |
|---|---|---|
| `POST /guests` | `{ language_pair?: "en-ru", level?: "A2" }` | `201 { token, user: { id, guest: true, language_pair } }` |
| `POST /sessions` | `{ email_address, password }` | `201 { token, user }` · `401 invalid_credentials`. With a guest token in the header, the guest's words and progress move into the account. |
| `DELETE /session` | — | `204` |

## Episodes

`GET /episodes/:id` — published episodes only.
`GET /s/:share_token` — a user story by its share link (the token from `https://<host>/s/<token>`).

- `200` episode JSON (below). Media URLs are absolute.
- `402 { error: "subscription_required", paywall: { plans } }` for a paid episode without access.
- `404 { error: "not_found" }`, also for a user story the client may not read (docs/user-stories.md, `StoryAccess`):
  a `link` story opens only through `/s/:share_token`, a `private` one only with its author's token,
  a hidden story or a banned author's for nobody else.

```jsonc
{
  "id": 1, "number": 1, "title": "The Wrong Order", "format": "webtoon",   // webtoon | manga | chat | illustrated
  "cefr_level": "A2", "free": true, "estimated_minutes": 4, "target_words": ["in a hurry"],
  "language_pair": { "code": "en-ru", "target_lang": "en", "native_lang": "ru" },
  "series": { "id": 1, "slug": "coffee-and-coincidences", "title": "Coffee & Coincidences" },
  "characters": [{ "id": 1, "key": "mia", "name": "Mia", "protagonist": true, "avatar_url": null }],
  "panels": [{
    "id": 1, "position": 0, "aspect_ratio": 0.8,
    "layout": { "aspect_ratio": 0.8 },                       // manga: { page, cols: 1|2 }
    "image_url": "https://…/phone.webp",                    // 800w WebP
    "image_srcset": "https://… 800w, https://… 1200w",
    "bubbles": [{
      "id": 1, "position": 0, "kind": "speech",               // speech | thought | narration | chat_message
      "character_id": 1, "text": "Everyone is in a hurry.", "translation": "Все спешат.",
      "box": { "x": 5, "y": 4, "w": 56, "h": 16 },            // percent of the panel image; null for chat/illustrated
      "audio_url": null,
      "tokens": [{
        "id": 7, "lexeme_id": 3, "start": 12, "end": 22,       // codepoint offsets: text[start...end] == surface
        "surface": "in a hurry", "translation": "спешат", "note": "…",
        "romanization": null, "breakdown": null, "politeness": null   // Korean: romanization, [{part, role, meaning}], casual|polite|formal
      }]
    }]
  }],
  "lexemes": { "3": { "id": 3, "lemma": "in a hurry", "pos": "phrase", "cefr_level": "A2",
                       "romanization": null, "translation": "в спешке", "audio_url": null } },
  "next_episode": { "id": 2, "number": 2, "title": "…", "locked": false },
  "user": { "guest": true, "saved_lexeme_ids": [3], "last_panel_position": 0, "completed": false }  // null without a token
}
```

Offsets are Unicode codepoints. In Swift use `text.unicodeScalars`, in Kotlin `text.codePoints()`, in JS `Array.from(text)` — not UTF-16 indices.

## Progress

`PATCH /episodes/:id/progress` `{ last_panel_position, completed }` → `{ last_panel_position, completed }`.
The position only moves forward. For chat it is the index of the last revealed message.

## Saved words

| Call | Body | Response |
|---|---|---|
| `GET /user_words` | — | `[{ lexeme_id, lemma, due, state }]` |
| `POST /user_words` | `{ lexeme_id, token_id? }` | `201 { lexeme_id, saved: true, due }` (idempotent) |
| `DELETE /user_words/:lexeme_id` | — | `204` |

Errors: `{ error: "<code>", message? }` with `401 unauthorized`, `404 not_found`, `402 subscription_required`,
`422 parameter_missing`, `429 rate_limited`.
