# storyloop_back

Rails 8.1 · Ruby 3.4 · PostgreSQL 16 · Hotwire · Tailwind v4. Всё запускается в Docker.

## Запуск

```bash
docker compose up                                            # http://localhost:3000
docker compose run --rm web bin/rails db:prepare db:seed     # первый раз: база + сиды
```

Dev-админ из сидов: `admin@storyloop.local` / `storyloop-admin` → http://localhost:3000/admin

Postgres из контейнера доступен на хосте на порту **5434** (`postgres` / `postgres`).

## Тесты

```bash
docker compose run --rm test                                 # unit + системные (Chrome в контейнере)
docker compose run --rm web bin/rails test                   # только unit/интеграционные
docker compose run --rm web bin/rubocop
```

Посмотреть системные тесты вживую: http://localhost:7900 (пароль `secret`).

## Контент

- Формат эпизода: `config/schemas/episode.json` (один и тот же для сидов, импорта и шага «Сценарий» AI-конвейера).
- Сиды: `db/seeds/episodes/<pair>/NN.json`. Проверка без базы:
  `docker compose run --rm web bundle exec ruby script/validate_episode.rb db/seeds/episodes/*/*.json`
- Импорт: `docker compose run --rm web bin/rails "episodes:import[path/to/episode.json]"` (`STATUS=published` чтобы сразу опубликовать) или форма `/admin/imports/new`.
- Позиции токенов — в символах (codepoints). Если в JSON их нет, импортёр находит слова в тексте по порядку.
- Без картинки у кадра генерируется плейсхолдер (WebP через libvips).

## Документы

- `docs/mvp-research.md` — исследование и принятые решения
- `docs/roadmap.md` — задачи по волнам, оценки и даты
- `docs/content-review.md` — вычитка сидов и факты сюжета
- `docs/style-options.html` — 5 направлений стиля (выбран A + ночная тема D)

## Структура

| Что | Где |
|---|---|
| Модели | `app/models` — LanguagePair, Series, Character, Episode, Panel, Bubble, Token, Lexeme, User, UserWord, ReadingProgress, GenerationLog, WaitlistEntry |
| Импорт эпизода | `app/services/episodes/importer.rb` |
| Админка | `app/controllers/admin`, `/admin`, доступ только `admin: true` |
| Стиль A (+ ночная тема D) | `app/assets/tailwind/application.css` |
