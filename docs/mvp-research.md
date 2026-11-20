# Storyloop — исследование и план MVP

Обновлено: 2026-11-21. Источник задачи: `mvp-prompt-language-comics.md`.

## 0. Принятые решения

| Вопрос | Решение |
|---|---|
| Стиль | **A «Бумага и маркер»** (Readwise + Oku) для всего продукта; **тёмная тема читалки — из D** (ElevenReader + Kippo). Макеты: `docs/style-options.html` |
| Окружение | **Docker с первого дня**: dev через `docker compose`, прод — тот же образ через Kamal 2 |
| AI | Начинаем с **дешёвых китайских API**, всё за адаптерами `app/services/ai/*`, провайдер меняется конфигом |
| Ruby | 3.4 внутри образа (локальный Ruby машины не важен) |
| Вход | Генератор Rails 8 (email + пароль) в волне 1; magic link — после PoC |
| Репозитории | Отдельные: `storyloop_back` (Rails + документы в `docs/`), `storyloop_mobile` (Hotwire Native — волна S, входит в PoC; в сторах без пейвола, оплата в приложении — после теста спроса) |
| План и сроки | `docs/roadmap.md` — задачи по волнам, оценки и даты |
| Маркетинг | **Контент-завод в коротких видео** (TikTok / Reels / Shorts) + **сторы с ASO**, платно — только продвижение лучших роликов. Основная пара для теста — **ko-en**, en-ru — мягкий запуск. **Контент-завод — отдельный проект, в `storyloop_back` не реализуется.** Подробно: `docs/marketing-channels.md` |

## 1. Docker

- `Dockerfile` — продовый, генерирует Rails 8.1 (multi-stage, jemalloc, Thruster). Используется Kamal.
- `Dockerfile.dev` + `compose.yaml` для разработки:
  - `web` — Ruby 3.4, код смонтирован томом, `bin/dev` (Puma + tailwind watcher), порт 3000;
  - `db` — `postgres:16`, том для данных;
  - `jobs` — Solid Queue (`bin/jobs`), в dev можно внутри Puma (`SOLID_QUEUE_IN_PUMA`).
  - Гемы в именованном томе `bundle`, чтобы не ставить заново на каждый запуск.
- Команды: `docker compose up`, `docker compose run --rm web bin/rails test`, `... bin/rails db:seed`.
- Системные тесты: Chrome в отдельном контейнере `selenium/standalone-chromium`, Capybara ходит в него по сети.
- Прод: Kamal 2 → один VPS (Hetzner), Postgres как accessory на том же сервере, файлы в Cloudflare R2.

## 2. Версии (rubygems, ноябрь 2026)

| Гем | Версия | Зачем |
|---|---|---|
| rails | 8.1.4.1 | Solid Queue/Cache/Cable, генератор auth, Kamal 2, PWA |
| tailwindcss-rails | актуальная | Tailwind v4 без Node |
| ruby_llm | 2.2.3 | чат, structured output, картинки; DeepSeek нативно, Qwen через OpenAI-совместимый `api_base` |
| fsrs_ruby | 1.0.0 | FSRS v6 (старый `fsrs` требует activesupport 7 — не берём) |
| pay + stripe | 13.0.1 | за флагом `PAYMENTS_MODE=stripe` |
| posthog-ruby | 3.34.3 | серверные события |
| image_processing | актуальная | WebP-варианты через libvips (есть в образе) |
| aws-sdk-s3 | актуальная | R2 для Active Storage |

## 3. AI-провайдеры: старт на дешёвых

Весь контент генерируется **заранее** конвейером. Данные пользователей к провайдерам не уходят.

| Шаг | Основной (дёшево) | Для сравнения | Цена (ориентир, проверить в консоли) |
|---|---|---|---|
| Сценарий + разметка токенов | **DeepSeek V4 Flash** | Qwen 3.5 Plus, Claude Sonnet 5.5 как «эталон» | DeepSeek Flash ≈ $0.2–0.3 вход / $0.7–1.2 выход за 1M токенов (есть пик/не пик); Qwen 3.5 Plus $0.4 / $2.4 |
| Картинки с одинаковыми персонажами | **Seedream 5.0** (BytePlus, до 10 референсов) | Nano Banana 2, GPT Image | Seedream от $0.045/картинка, доп. референс ~$0.003 |
| Озвучка | **MiniMax Speech 2.8 Turbo** | Google Chirp 3 HD, ElevenLabs | MiniMax $60/1M символов (корейские символы, вероятно, считаются ×2); Chirp 3 HD ≈ $30/1M |

**Оценка себестоимости эпизода** (10 кадров, ~25 пузырей, ~1500 символов):
LLM < $0.05 + картинки ≈ $0.5 + озвучка ≈ $0.1–0.2 → **≈ $0.7 за эпизод**, плюс перегенерации.
Точные цифры покажет `GenerationLog` и страница «Себестоимость».

**Риски дешёвых моделей и что делаем:**
- Невалидный JSON / сбитые offsets → валидация по JSON Schema + проверка `text[start...end] == surface`, повтор с текстом ошибки (до 3 раз), иначе шаг падает в `review`.
- Качество корейского разбора → на M6 прогон 20 реплик через DeepSeek / Qwen / Claude, сравниваем в админке. Можно смешивать: сценарий дешёвой моделью, разметку — сильной.
- Доступ из РФ/оплата → провайдеры за адаптером, переключение конфигом; OpenRouter как запасной шлюз (ruby_llm его поддерживает).

## 4. Модель данных (поправки к промпту)

- `Token`: + `breakdown jsonb` (ko: основа + окончание/частица), `politeness` (반말/존댓말), `romanization`.
- `Bubble.box`: `jsonb {x, y, w, h}` в процентах.
- Гость = `User` с `guest: true` без email и пароля, сессия обычная (cookie). Регистрация дописывает email и пароль в ту же запись, переносить ничего не нужно; слияние — только если гость входит в уже существующий аккаунт.
- `WaitlistEntry`: email, language_pair, utm, source — для fake door.
- Offsets токенов — в символах (codepoints): Ruby `String#[]`, в JS `Array.from(text)`. Иначе корейский и эмодзи поедут.
- `Lexeme` уникален по `(language, lemma, pos)`; `translations jsonb` по родным языкам.

## 5. Этапы

Порядок: читалка и воронка на ручных эпизодах → видео-завод → AI-конвейер → сторы. Тест спроса начинается с роликов, ведущих в веб; сторы подключаются по мере ревью.
Задачи, оценки и даты по волнам — в `docs/roadmap.md`.

## 6. Визуальный стиль — токены (для M1)

Светлая тема (весь продукт):
`paper #fbf9f3` · `panel #ffffff` · `ink #333333` · `ink-strong #161616` · `muted #7b7a79` · `edge #dbd7cd` · `recess #f5f1e8` · `marker #f9e874` · `marker-soft #f9ed9e` · `link #2675de` · `warm #ff8904`

Тёмная тема читалки (D):
`bg #0e0e12` · `sheet #1b1b22` · `edge #2c2c36` · `fg #ececf1` · `accent #f58971` · `saved #7767d8`

Шрифты: Source Serif 4 (текст историй, заголовки) + Inter (интерфейс) + Noto Sans KR / Noto Serif KR (хангыль). Кнопки — тёмные пилюли 40px радиус; сохранённое слово — маркер (светлая) / фиолетовое подчёркивание (тёмная).
