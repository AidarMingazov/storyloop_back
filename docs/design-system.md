# Дизайн-система Storyloop

Волна Р1 (21.11.2026). Живая витрина всех токенов и компонентов в двух темах: **/admin/styleguide**. Макеты читалки и план волн Р: `docs/reader-design/index.html`.

## Темы и токены

Один набор семантических токенов в `app/assets/tailwind/application.css` (`@theme static`), две темы:

- **Бумага** — по умолчанию.
- **Полночь** — `<html data-theme="night">` (ночной режим читалки) или класс `.theme-night` на любом элементе.

| Токен | Утилиты | Для чего |
|---|---|---|
| `bg`, `bg-2` | `bg-bg`, `bg-bg-2` | фон страницы; подложки, чипы |
| `surface`, `raised`, `chip` | `bg-surface`, `bg-raised`, `bg-chip` | карточки и поля; шторка, поповер, плеер; нейтральные кнопки |
| `fg-strong`, `fg`, `fg-2` | `text-fg-strong`, `text-fg`, `text-fg-2` | заголовки и текст истории; текст интерфейса; вторичный текст |
| `line`, `line-2` | `border-line`, `border-line-2` | разделители; контуры контролов |
| `accent`, `on-accent`, `accent-soft` | `bg-accent`, `text-accent` | действие чтения, голос, прогресс |
| `marker`, `hl-saved`, `marker-ink` | `bg-marker` | слово в карточке; полоса под сохранённым словом |
| `success`, `error` | `text-success`, `text-error` | состояния |
| `bubble*` | `bg-bubble`, `text-bubble-ink` | пузыри: бумажные в обеих темах, не переключаются |

Старые имена стиля A (`paper`, `panel`, `recess`, `pebble`, `edge`, `ink`, `ink-strong`, `muted`, `link`) остались и смотрят на семантические токены — существующие вьюхи не переписывались. В новом коде — семантические имена.

Правила:
- Одно действие на экран — `btn-accent`. Общие действия приложения — `btn-primary` (чернила).
- Маркер — только для слов. Акцент — только для действий, голоса и прогресса.
- Никаких hex в вьюхах и JS: если цвета не хватает, это новый токен в обеих темах.
- Никаких эмодзи в интерфейсе: иконки из спрайта.

## Компоненты (CSS-классы)

`btn-primary`, `btn-accent`, `btn-secondary`, `btn-ghost`, `btn-saved`, `btn-danger`, размеры `btn-sm`, `btn-lg`; `btn-icon`, `btn-icon-soft`; `chip` (`aria-pressed`), `tag`, `badge-*`; `seg` (сегменты: режим, язык, уровень); `switch` + `switch-knob` (`role="switch" aria-checked`); `progress`; `sheet` + `sheet-handle` (шторка без затемнения), `popover` (`--arrow-x`, `is-above`); `modal` (на `<dialog>`); `toast`; `empty-state`; `skeleton`; `kbd`; `bubble`; состояния слова `word-open`, `word-saved`, `word-speaking`.

Читалка пока на своих классах (`reader-*`, `word-sheet`, `wt-bubble`), но они уже на тех же токенах; волна Р2 переводит её на общие компоненты.

## Иконки

Спрайт `app/views/shared/_icons.html.erb` подключён в раскладках `application`, `reader`, `admin`. Линия 24px, 1.8, цвет — `currentColor`.

- Сервер: `icon(:play)`, `icon(:lock, label: "Только по подписке")`, `icon(:bookmark_fill, class: "size-6")`.
- Клиент: `import { icon, setIcon } from "reader/icons"`; `setIcon(svg, "bookmark-fill")` меняет символ на месте (не пересоздавайте узел, по которому только что кликнули).
- Новый значок: `<symbol id="i-…">` в спрайте + имя в `DesignHelper::ICONS` (тест сверяет списки).

## Шрифты и письменности

Source Serif 4 (заголовки, текст на латинице), Inter (интерфейс), Noto Sans KR / Noto Serif KR — на всех страницах. Noto Sans JP и SC грузятся только если страница попросила: `use_fonts_for pair.target_lang` (читалка, повторение).

Текст на изучаемом языке выбирает шрифт по `lang`: классы `story-text`, `sheet-word`, `review-text`, общий `script`. Для `ko` — `word-break: keep-all`, для `ja`/`zh` — `line-break: strict`; курсив для мыслей только на латинице. Руби (`<ruby><rt>`) — для романизации, фуриганы и пиньиня.

## Ещё на эмодзи

Админка (внутренняя) и экраны генератора историй (`stories/*`, `voice_input_controller.js`, темы в `Stories::Themes`) — переводятся вместе с редизайном генератора (волна Р5).
