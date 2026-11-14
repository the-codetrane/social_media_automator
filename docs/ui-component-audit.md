# UI audit: Social Media Automator vs. the 2100 component library

_Audited 2026-11-14 against `component_library_2100` v0.12.3, by walking every signed-in page on `localhost:3000` (desktop at 1280px, plus a phone-width pass) and reading `app/views`, `app/helpers` and `app/javascript/controllers`._

## Decisions this plan assumes

| Question | Decision |
|---|---|
| Visual direction | **Keep the current indigo look.** Adopt the components and retheme the library's tokens to match the app. |
| Adding to the library | **Only for generic patterns** that other 2100 apps would plausibly use. App-specific pieces stay in this app as ViewComponents. |
| CSS build | **Move this app from `cssbundling-rails` (npm Tailwind CLI) to `tailwindcss-rails`**, so the library's standard install path works unchanged. |

## Summary

The app doesn't use the library at all yet. Every button, badge, input, modal, dropdown, table and empty state is hand-written Tailwind, repeated page by page:

| Pattern repeated in `app/views` | Count | Library replacement |
|---|---|---|
| Uppercase `dt` labels (`uppercase tracking-wide`) | 125 | `ui_description_list` / `ui_stat` |
| Inline `<svg>` icons | 70 | Unchanged, but most sit inside buttons that become `ui_button` |
| Text inputs with hand-written focus styles | 48 | `ui_form_with` (FormBuilder) |
| Indigo primary buttons | 41 | `ui_button` |
| Pill badges (`rounded-full text-xs font-medium`) | 35 | `ui_badge` + two app-level badge components |
| `form_with` forms | 21 | `ui_form_with` |
| `turbo_confirm` uses (browser `confirm()`) | 11 | `ui_confirm_dialog` + `useStyledConfirm` |
| Ad-hoc empty states | 8 | `ui_empty_state` |
| `<table>`s | 7 | `ui_table`, `ui_sort_header` |

Five of the app's 17 Stimulus controllers (`dropdown`, `modal`, `collapse`, `carousel`, `debounced_search`) duplicate library behaviour, and two more (`audio_select`, `collaborator_select`, 450 lines between them) are close to the library's Combobox.

**Recommended order:** fix the bugs below → install and theme the library → swap the global shell (nav, flash, confirm) → swap shared primitives (buttons, badges, forms) app-wide → page-by-page refactors → library additions.

---

## 1. Bugs found during the walkthrough

Fix these regardless of the refactor. Several go away on their own once the shared components are in.

| # | Issue | Where | Fix |
|---|---|---|---|
| B1 | **Flash messages render twice.** The layout renders `notice`/`alert`, and 11 views also render `flash[:notice]`/`flash[:alert]` themselves, so on those pages the same message appears twice. (Found by reading the code; the layout and the views read the same flash.) | `planned_posts/show`, `media_assets/show`, `social_templates/show`, `known_people/show`, `users/show`, `admin/{instagram,youtube,tiktok}/auth/connect`, `sessions/new`, `passwords/{new,edit}` | Delete the per-view blocks and render flash once, in the layout (see §3.2). |
| B2 | **Admin › Users table is cut off at phone width.** The Actions column (View/Edit/Delete) is off-screen with no horizontal scroll, and dates wrap onto three lines. | `admin/users/index` | `ui_table responsive: true` with a caption (it becomes a keyboard-scrollable region), and collapse the row actions into a `ui_dropdown` "⋯" menu. |
| B3 | **Planned Posts selection checkboxes have no accessible name.** Media Assets' have `aria-label="Select …"`; Planned Posts' don't, in either the card or the table view. | `planned_posts/index` | Add `aria-label`, or use the bulk-select component proposed in §6. |
| B4 | **Nav dropdowns aren't accessible.** The Content/Analytics menus and the mobile drawer are toggled by `dropdown_controller` with no `aria-expanded`, no Escape and no arrow keys, and the hamburger drawer has no focus handling. | `shared/_nav` | `ui_navbar` + `ui_dropdown` (popover API + `<dialog>` offcanvas). |
| B5 | **Sort direction is shown only as a text arrow** (`↑`/`↓`), with no `aria-sort`. | `ApplicationHelper#sort_link_to` | `ui_sort_header`. |
| B6 | **The Instagram logo is hotlinked from Wikimedia.** That's a third-party request on an admin page, and it breaks if they move the file. | `admin/instagram/auth/connect` | Serve a local SVG asset. |
| B7 | **`/media_assets/new` visited directly renders the modal's form as a bare full-width page** (title, ✕ and Cancel with no page chrome). It's built to load into the upload `<dialog>`'s Turbo Frame. | `media_assets/new` | Wrap it in a layout check (`turbo_frame_request?`), or give the standalone version a `ui_page_header` and a card. |
| B8 | **The login card is `bg-blue-50`**, unlike every other card in the app (white). | `sessions/new` | `ui_card`. |
| B9 | **Dev-only:** if the marketing app (which registers a 2100 service worker) has ever run on `:3000`, Chrome serves its "You're offline" page for SMA whenever SMA's server is down. | Local dev | Run the apps on different ports, or unregister the worker in DevTools › Application. Adopting the library's PWA kit (§7, optional) would give SMA its own worker. |

---

## 2. Install and theme (Phase 0)

### 2.1 Move to `tailwindcss-rails`

The marketing app (`2100-enterprises-marketing-app`) already runs this setup and is a working reference.

1. **Gemfile:** remove `cssbundling-rails` and add `tailwindcss-rails` and `component_library_2100`:
   ```ruby
   gem "tailwindcss-rails"
   gem "component_library_2100", github: "2100-Enterprises/2100-component-library", tag: "v0.12.3"
   ```
2. **Move the stylesheet:** `app/assets/stylesheets/application.tailwind.css` → `app/assets/tailwind/application.css`, keeping the `.chat-markdown` rules. Delete `app/assets/builds/application.css` from version control if it's tracked (`tailwindcss-rails` writes `app/assets/builds/tailwind.css`), and update `stylesheet_link_tag "application"` → `stylesheet_link_tag "tailwind"`, or keep the name by configuring the output path.
3. **Procfile.dev:** `css: yarn watch:css` → `css: bin/rails tailwindcss:watch`.
4. **Remove Node from the build:** delete `package.json`, `yarn.lock`, `package-lock.json` and `node_modules`, and in the `Dockerfile` drop the NodeSource/yarn install (lines 33–38) and the `COPY package.json yarn.lock* ./` + `yarn install` steps (lines 51–52). `tailwindcss-rails` hooks `tailwindcss:build` into `assets:precompile`, so the image build needs no extra step. This makes the image smaller and the build faster.
5. **CI:** check `bin/ci` and `.github/workflows` for any `yarn`/`build:css` step.
6. **Install the library:** `bundle install && bin/rails g component_library_2100:install`. That adds the CSS import, registers the `cl-*` Stimulus controllers, and gitignores the generated `component_library_2100.css`.
7. **Styled confirms:** add `<%= ui_confirm_dialog %>` to the layout and `useStyledConfirm(Turbo)` to `application.js`. All 11 existing `turbo_confirm`s then get a real dialog instead of the browser's `confirm()`, with no other changes.
8. **Forms:** `config.action_view.default_form_builder = "ComponentLibrary2100::FormBuilder"`, so forms can be migrated one at a time just by removing their hand-written classes.

For local library development: `bundle config local.component_library_2100 ../2100-component-library`.

### 2.2 Retheme to indigo

Put this in `app/assets/tailwind/application.css` **after** the library import. These values reproduce what the app uses today:

```css
@import "tailwindcss";
@import "./component_library_2100.css";

@theme {
  /* Primary = the app's indigo */
  --color-primary:          var(--color-indigo-600);
  --color-primary-on:       #fff;
  --color-primary-subtle:   var(--color-indigo-50);
  --color-primary-border:   var(--color-indigo-200);
  --color-primary-emphasis: var(--color-indigo-700);
  --color-link-hover:       var(--color-indigo-700);

  /* Neutrals = Tailwind gray, which the app uses everywhere */
  --color-body:           var(--color-gray-900);
  --color-body-muted:     var(--color-gray-600);
  --color-border:         var(--color-gray-200);
  --color-border-subtle:  var(--color-gray-100);
  /* gray-300 is what the app uses, but it's ~1.5:1 on white. The marketing app
     moved to slate-500 for a 3:1 field edge. gray-400 is a reasonable middle. */
  --color-border-input:   var(--color-gray-400);
  --color-surface-subtle: var(--color-gray-50);
  --color-surface-muted:  var(--color-gray-100);

  /* Radii: the app's buttons/inputs are rounded-lg, cards rounded-xl */
  --radius-ui-sm: 0.375rem;
  --radius-ui:    0.5rem;
  --radius-ui-lg: 0.75rem;
}
```

Then set `<body class="bg-surface-subtle text-body">` and replace `text-indigo-*` and `bg-indigo-*` in views with token classes (`text-primary`, `bg-primary-subtle` and so on) as each file is touched, so a later retheme only touches this block.

**Platform brand colours** (Instagram pink, YouTube red, Facebook blue, TikTok black) are app-specific. Define them as app tokens (`--color-instagram`, …) in this file and use them from the `PlatformBadge` component in §5, not from the library's variants.

---

## 3. Global shell (Phase 1)

These are a few files, but every page benefits.

### 3.1 Navigation: `shared/_nav.html.erb` (119 lines → ~30)

Replace it with `ui_navbar label: "Main", expand: :sm, theme: :surface`. Then:

- `with_brand(href: root_path)` for the logo + "SMA".
- `with_item` for Users, Admin (admins only), Chat and Known People. `active:` handles `aria-current`.
- **Content** and **Analytics** are grouped menus, which `NavbarComponent` doesn't support yet (items are plain links). See library addition **L1**. Until it lands, either flatten them into top-level items or put a `ui_dropdown` inside `with_actions`, which only works on desktop.
- `with_actions` holds a `ui_dropdown` account menu: the user's `ui_avatar`, then "Sign out" (`method: :delete`). That replaces the bare "Sign out" link.
- That removes the hand-built mobile drawer, the `active_name` case statement, and `dropdown_controller.js` (once nothing else uses it).

### 3.2 Flash messages: `layouts/application.html.erb`

Render flash once, as `ui_alert notice, variant: :success, dismissible: true` / `ui_alert alert, variant: :danger, dismissible: true`. That replaces the inline `onclick="this.closest('div').remove()"` (which a strict CSP would block) with `cl-dismiss`. Alternatively, use `ui_toast_container` + `ui_toast` so messages don't push content down. Toasts suit transient confirmations ("Post rescheduled"); keep `ui_alert` for errors that need reading, such as the insights "Could not load insights: Invalid OAuth access token" message. Then delete the per-view flash blocks (B1).

### 3.3 Footer and pagination

- **Pagination** (`shared/_pagination.html.erb`): use `ui_pagination` with Prev / numbered pages / Next. Keep the "Showing 1–12 of 40" text beside it. A `ui_pagy(pagy, frame:)` helper in the app keeps call sites one line. (If other 2100 apps use pagy, this helper is a candidate for the library; see L6.)
- The footer can stay as it is (it's three links). Just swap its gray classes to tokens.

---

## 4. Shared primitives (Phase 2)

Apply these across all views. Each one is mechanical and can be done file by file.

| Today | Replace with | Notes |
|---|---|---|
| `link_to …, class: "inline-flex … bg-indigo-600 text-white …"` and similar | `ui_button "Edit", href: …, variant: :primary` | Red "Delete" → `variant: :danger`; outlined "Archive"/"Cancel" → `outline: true, variant: :secondary`; `button_to` → `ui_button` inside `button_to`, or `ui_dropdown` items with `method:`. Icons stay as block content; the button is `inline-flex`, so they line up. |
| The pink `Publish to Facebook` button (`bg-pink-600`) | `ui_button variant: :primary` (or `:success`) | Pink reads as "Instagram" elsewhere in the app, so it's misleading on a Facebook post. If the platform should show, put a `PlatformBadge` inside the button. |
| `status_color_classes` / `platform_color_classes` spans (35×) | `StatusBadge` and `PlatformBadge` app components (§5) | Map status → library variants: draft→`secondary`, scheduled→`primary`, published→`success`, failed→`danger`, canceled→`warning`. Media status: discovered→`warning`, processed→`success`, failed→`danger`. |
| Hand-written inputs, labels, hints and errors (48 inputs) | `ui_form_with` + `f.text_field`, `f.select`, `f.text_area`, … | Gives labels, `aria-describedby`, `aria-invalid` and `f.error_summary` for free. |
| `<dl>` grids of uppercase labels (125×) | `ui_description_list layout: :inline` | Detail pages: post, asset, template, user, known person. The library's term style (`text-sm font-medium`) is calmer than the current all-caps; keep it. Card footers and side panels can keep a compact style via `class:`. |
| Big number + small label (`Planned posts 0`, LLM stat cards) | `ui_stat` / `ui_stats` | LLM Costs, Insights show, the counts on user/asset/template detail pages. |
| `"No … found."` divs (8×) | `ui_empty_state` | With an action where one makes sense ("Upload media", "New template"). Known People's empty state is already close; it just becomes the component. |
| `← back arrow + h1 + action buttons` header row (every show/edit page) | `ui_page_header` | Back link: see L4. |
| Index header (`h1` + "12 records") | `ui_page_header title:, subtitle:` | Planned Posts, Media Assets, Templates, Insights, Users, Sessions, Known People. |
| `<table>` + `sort_link_to` | `ui_table hover: true, responsive: true` + `ui_table_header` + `ui_sort_header` | Planned Posts, Media Assets, Admin Users, LLM Costs (×2), Insights metrics. Give each a caption (`visible: false` is fine). Retire `sort_link_to`. |
| "Additional Details" disclosure (`collapse_controller`) | `ui_accordion` (one item) or `ui_collapse` | Post, asset and template show pages, and the chat model panel on mobile. `<details>`-based, no JS. |
| `modal_controller` + raw `<dialog>` | `ui_modal` | Media upload modal, reschedule modal, bulk delete modal. Bulk delete should be a `ui_modal` with a danger button, or route through the styled confirm. |
| `turbo_confirm` (11×) | No change at call sites | Becomes a styled `alertdialog` after §2.1 step 7. Add `data-turbo-confirm-accept="Delete"` on destructive ones. |
| Initials circles (`TV`, `MC`, …) | `ui_avatar name: user.name` | Users index/show, Admin users index/show, sessions. |
| Boolean checkbox + description ("Admin – Can manage users…") | `f.switch :admin, hint: "…"` | Admin invite/edit. |
| "Post type: Single / Carousel / Story" radios | `f.radio_cards :post_type, [...], columns: 3` | Bigger touch targets, and room for a one-line description per type. |
| `datetime-local` field | `f.datetime_local_field :scheduled_at, min: Time.current` | Same native picker, wrapped. |
| Password + confirm fields | `f.password_field` (built-in Show/Hide toggle, `counter: {min: 12}`) | Admin "Set password", registrations, password reset. |
| File inputs (`file:` classes) | `f.file_upload` | Known People reference photo, chat attachment, media upload (see §5.2). |

---

## 5. Page-by-page

### 5.1 Content › Planned Posts

**Index** (`planned_posts/index.html.erb`, 470 lines). This is the densest page and gains the most.

- Header → `ui_page_header` with the view toggle in `with_actions`.
- **Platform filter chips** (four hand-written `peer-checked` labels, each with its own colour) and **status segmented control**: no library equivalent. See **L2 (ToggleGroup)**. With it, this block drops from ~90 lines to ~10, and `filter_form_controller` becomes `cl-autosubmit`.
- **Card/table view toggle**: the two icon buttons become a two-option ToggleGroup (L2) with `aria-pressed`. Persisting the choice (`view_toggle_controller`, localStorage) stays app-level.
- **Bulk action bar + selection checkboxes**: see **L3 (BulkSelect)**. It's the same pattern as Media Assets, and the hand-rolled custom checkbox SVG is pasted four times across the two pages.
- **Cards**: `ui_card` with a media slot (L5), `StatusBadge` + `PlatformBadge`, and `ui_description_list` for the metadata. Many cards show a grey placeholder because the seed assets have no URL, so make the placeholder smaller, or hide it when no post on the page has media, so the grid isn't mostly empty grey boxes.
- **Table**: `ui_table` + `ui_sort_header`. Add an `aria-label` to the row checkbox (B3) and an accessible name to the trailing chevron link ("View post …").
- **Empty state** → `ui_empty_state` with a hint to change filters.
- **Reschedule / Delete modals** → `ui_modal` (focus trap, Escape and the inert page come from the library).

**Show** (309 lines)

- Header → `ui_page_header` with a back link and prev/next (L4). Actions: Publish (primary), Edit (`outline`), Delete (danger, `outline`). Three solid colours side by side (pink, indigo, red) compete. Move Delete and Re-verify into a "⋯" `ui_dropdown` and keep one primary action.
- Badges → `PlatformBadge` + `StatusBadge`.
- Fields → `ui_description_list layout: :inline`.
- "Additional Details" JSON → `ui_accordion`.
- Remove the duplicate flash block (B1).

**Edit** (206 lines + `_instagram_options` 85 lines)

- `ui_form_with`. The reuse warning ("This post reuses media") → `ui_alert variant: :warning`. Status → `f.select`, Scheduled At → `f.datetime_local_field`, Post Type → `f.radio_cards`, Media Asset → `f.select` (the grouped options helper still works). Caption → `f.text_area counter: {max: template max_caption_length}`, a live counter the app currently lacks.
- "Reference information" → `ui_description_list layout: :inline, dividers: false`.
- **Audio picker** (`audio_select_controller`, 224 lines) → `f.combobox :audio_id, src: audio_search_planned_post_path(@planned_post)`. The endpoint must render `ui_combobox_option`s in the requested Turbo Frame. Title/artist can ride along as hidden fields filled from the option's data, via a small app listener.
- **Collaborators** (`collaborator_select_controller`, 226 lines) is a multi-value, free-entry chip input capped at 3. Combobox is single-value, so see **L7 (Combobox multiple/tags mode)**. Until then, keep the controller but render its chips with `ui_chip` / `ui_chip_group`.

### 5.2 Content › Media Assets

**Index** (420 lines)

- Header → `ui_page_header`, with "Upload media" as `ui_button` in `with_actions`.
- **Availability tabs** (hand-built underline links) → `ui_nav style: :tabs, label: "Filter by availability"`. It's a direct match, including `aria-current`.
- Search → `ui_input_group` with a search-icon prepend, or `f.search_field` in a `ui_form_with`. `debounced_search_controller` can stay, or move to `cl-autosubmit` if it learns a delay (worth adding to the library: `autosubmit` with `delay:`).
- Bulk bar / selection → L3. Cards → `ui_card` + media slot (L5). Table → `ui_table`. `opacity-60` for archived cards → a `secondary` "Archived" badge plus reduced opacity, so it isn't communicated by fade alone.
- Upload modal → `ui_modal` around the existing Turbo Frame (`turbo:frame-load` → `cl-dialog#open`).

**New / upload** (`media_assets/new`, `media_upload_controller` 156 lines)

- Folder select → `f.select`. Show the "new folder" input with `ui_collapse`, or keep the small toggle.
- Files → `f.file_upload :files, multiple: true, dropzone: true, accept: %w[image/* video/*], direct_upload: true`. The library's FileUpload already does the file list, remove buttons, size/type warnings, live announcements and direct-upload progress. **Check before deleting the controller:** uploads go to a custom URL (`MediaAssets::DirectUploadsController`) with the chosen folder. Setting `data-direct-upload-url` on the input covers the URL. Whether the folder can be passed the same way (or read server-side from the form) decides whether the controller shrinks to ~20 lines or can go entirely.
- Fix B7.

**Show** (235 lines) → `ui_page_header` (Archive as `outline`, Edit), `ui_description_list`, `ui_stat` for "Planned posts", `ui_accordion` for "Additional Details". If the page shows a carousel for multi-item assets, it becomes `ui_carousel` (keyboard, swipe, ARIA), and `carousel_controller.js` goes.

**Edit** → `ui_form_with`, `f.text_field :name, hint:`, `f.select :status`, reference info as an inline `ui_description_list`.

### 5.3 Content › Templates

- **Index**: cards → `ui_card` with header (name + `PlatformBadge`), a `ui_chip` for owner ("Global Template" or the user's name, replacing the 👤/🌐 emoji spans), and `ui_description_list` for max caption and aspect ratio. **The raw `settings` JSON in each card** (`{"auto_hashtags":false,…}`) is noise on an index page. Show it as 2–3 small badges ("Auto-hashtags", "Evening") or move it to the show page only.
- **Show**: same as the other show pages. Delete → styled confirm.
- **New / Edit**: `ui_form_with`. Max caption length and aspect ratio side by side are fine, using a grid wrapper with `f.number_field` / `f.text_field` (`hint:` already exists).

### 5.4 Known People

- **Index**: the empty state → `ui_empty_state` with icon and action, matching what's there now. Populated: `ui_card` grid, with `ui_avatar` (or the reference photo) per person.
- **New / Edit**: `f.file_upload :reference_image, accept: "image/*"`. The "Upload or paste a CDN URL" choice is clearer as `f.radio_cards` ("Upload a photo" / "Use an existing URL") revealing one field, rather than two fields with an "OR" rule, which allows filling both.
- **Show**: `ui_page_header` and `ui_description_list`. Remove the duplicate flash (B1).

### 5.5 Chat

- Header → `ui_page_header`. "Clear" → `ui_button outline: true, variant: :danger` (keeps the confirm).
- **Model panel**: the list of models is effectively a single choice. Render it as `ui_radio_card_group` (name + one-line description, with pros/cons in each card's description) in a form with `cl-autosubmit`. That replaces the panel markup and gives keyboard selection. On mobile, wrap it in `ui_collapse` instead of `collapse_controller`, or in a `ui_offcanvas` ("Change model") so it doesn't push the chat down.
- Attachment input → `ui_file_upload` (no dropzone) inside the composer; the send button → `ui_button`.
- Thinking indicator → `ui_spinner size: :sm` with visually hidden "Thinking…".
- Leave the message bubbles and `.chat-markdown` app-level; they're specific to this page.

### 5.6 Analytics › Insights

- **Index**: `ui_page_header` (subtitle "9 published posts with data"), `ui_card` per post with `PlatformBadge` + `StatusBadge`, and `ui_description_list` for published/owner. "View Insights" → `ui_button outline: true, size: :sm`. Showing `published` as a badge on every card is redundant, since the page only lists published posts. Drop it.
- **Show** (`_instagram_metrics`, `_facebook_metrics`): headline numbers → `ui_stats columns: 4` (reach, impressions, likes, saves…), with `change:`/`trend:` where a previous value exists. Keep the Chartkick charts in `ui_card`s. When the API fails (the OAuth-token error I hit on `/insights/23` redirected back to the index with a red flash), show a `ui_alert variant: :warning` **on the show page** with a "Reconnect Instagram" button linking to `admin_instagram_connect_path`, rather than bouncing back to the list.

### 5.7 Analytics › LLM Costs

- Four stat cards (`llm_costs/_stat_card`) → `ui_stats columns: 4`. Delete the partial.
- "By Model" and "Daily Breakdown" → `ui_table` with captions and right-aligned numeric columns (`ui_sort_header … align: :end` if they become sortable).
- "No usage data available." → `ui_empty_state`. Today "By Model" shows a table with only a zero "Total" row when there's no data. Show the empty state for the whole page instead.

### 5.8 Users, Admin and Sessions

- **Users index**: `ui_card` + `ui_avatar` + status badge. "✕ Not Connected" / "Token Expired" → `ui_badge variant: :danger` / `:warning` (the `✕` and 🔴 glyphs are read aloud; use the text). Consider a `ui_table` instead: 12 users × 3 data points fits a table better than 12 cards, and it would match Admin › Users.
- **Admin users index**: `ui_page_header` with YouTube / TikTok / Invite actions. The YouTube and TikTok brand-coloured buttons link to *connection settings*, which isn't obvious from a red "YouTube" button next to "Invite User". Group them in a `ui_dropdown` "Integrations ▾" (Instagram, YouTube, TikTok), so all three platforms are reachable from one place (Instagram currently has no button here). Table → `ui_table responsive: true`. Row actions → "⋯" `ui_dropdown` (fixes B2). Role → `ui_badge`; token status → `ui_badge variant: :warning`.
- **Admin user show**: `ui_page_header` (back link, Edit `outline`, Resend invite, Delete danger `outline`), `ui_description_list`, and the "Set Password" panel as a `ui_card` with `f.password_field` ×2. The "Update Password" button is `bg-gray-800`, the only dark button in the app. Use `ui_button variant: :primary`.
- **Admin new/edit** → `ui_form_with`, `f.switch :admin, hint:`. Edit's "Save" and "Cancel" buttons are full-width side by side, while every other form has right-aligned Cancel (link) + Save. Pick one convention (see the form footer in §5.10).
- **Users show/edit** (self-service) → `ui_page_header`, `ui_description_list`, `ui_form_with`.
- **Sessions**: 59 cards, each showing a truncated user agent. That's a table: `ui_table` with User (`ui_avatar`), IP, device (parse the UA to "Chrome on macOS"), created, last active, and a `ui_badge` "Current". Add pagination.

### 5.9 Integrations: `admin/{instagram,youtube,tiktok}/auth/connect`

Three near-identical pages (60–110 lines each). Extract an app-level `IntegrationCardComponent(platform:, connected:, account:, expires_at:)` that renders `ui_card`, a status `ui_badge`, and the Connect / Refresh / Reconnect / Disconnect `ui_button`s. TikTok's sandbox/production mode switch → `ui_radio_card_group` with `cl-autosubmit` (the existing confirm stays on the form). Local logo assets (B6).

### 5.10 Auth pages: `sessions/new`, `registrations/new`, `passwords/{new,edit}`

`ui_card` on `bg-surface-subtle` (fixes B8), `ui_form_with` with `f.email_field` / `f.password_field` (Show/Hide toggle comes free), and `f.submit` full width. Remove the per-page flash blocks (B1). The layout's alert covers them once.

**Form footer convention** (all forms): right-aligned `[Cancel (link-style ui_button variant: :secondary, outline)] [Save (primary)]`, separated by a top border. The app already does this on most forms; Admin edit and Invite are the exceptions.

### 5.11 Public pages: `pages/home`, `tos`, `privacy`

Out of scope for component work. They're review-facing static pages. Swap colours to tokens when the palette moves, and leave the structure.

---

## 6. App-level components to build

These are specific to this app, so they stay in `app/components/`.

| Component | Replaces | Built on |
|---|---|---|
| `PlatformBadgeComponent(platform:)` | `platform_color_classes` + `platform_display_name` call sites (and the lower-case `capitalize`d `youtube` → "Youtube" bug: the helper says "YouTube", but views print `post.platform` with `capitalize`) | Subclass `ComponentLibrary2100::BadgeComponent`, using the app's `--color-<platform>` tokens via `class:`. |
| `StatusBadgeComponent(status:, kind: :post / :media)` | `status_color_classes`, the inline `status_colors` hash in `media_assets/index` | `BadgeComponent` with the variant mapping in §4. |
| `MediaThumbnailComponent(asset:, size:)` | Image/video/placeholder branches pasted into the planned post cards, media cards and show pages | Plain ViewComponent, used inside the Card media slot (L5). |
| `IntegrationCardComponent` | The three connect pages | `CardComponent`, `BadgeComponent`, `ButtonComponent`. |
| `ui_pagy` helper | `shared/_pagination` | `PaginationComponent`. |

---

## 7. Proposed library additions

These are filtered to **generic patterns another 2100 app would plausibly use**. Each one lists what it replaces here, so it can be justified in the library PR. Ordered by value.

| # | Addition | Why it's generic | Replaces in SMA | Size |
|---|---|---|---|---|
| **L1** | **Navbar menus**: `navbar.with_menu("Content", active:) { \|m\| m.with_item(...) }`. A dropdown in the bar on desktop, and a labelled group in the offcanvas on mobile. | Any app with more than ~6 sections needs grouped nav, and Navbar items are links only today. | `shared/_nav`'s two dropdowns and the hand-built mobile drawer. | M |
| **L2** | **ToggleGroup**: a set of checkbox (multi) or radio (single) inputs styled as pills or a segmented control, `autosubmit:`, optional icon-only options with visually hidden labels, and per-option `variant:`. | Filter bars and view switches are in every list-heavy app. It's the form-field counterpart of Chip (which displays a chosen value). | Platform chips, status segmented control and card/table toggle on Planned Posts; the view toggle on Media Assets. | M |
| **L3** | **BulkSelect**: a `cl-bulk-select` controller and a `BulkActionBarComponent` (sticky bar with "N selected", action slots and Clear). A "select all on page" checkbox in table headers, and a `selection_checkbox` helper with a required `label:`. | Every admin/list screen grows bulk actions. | `bulk_select_controller.js`, both action bars, and four copies of the custom checkbox markup. Fixes B3. | M |
| **L4** | **PageHeader `back:` and pager**: `back: {href:, label:}` renders a labelled back link before the title; `with_pager(prev:, next:)` renders "Previous/Next" icon links with accessible names. | Detail pages in any CRUD app. | The back-arrow + prev/next markup on every show/edit page (most have unlabelled icon links). | S |
| **L5** | **Card media slot**: `card.with_media(aspect: :video) { … }` for arbitrary top content (video, placeholder, map) alongside the existing `image_top(src:)`. Plus `href:` on Card to make the whole card a link while nested controls (checkbox, menu) stay clickable. | Gallery/grid cards are common, and `image_top` only takes a `src`. | The card wrappers on Planned Posts, Media Assets and Insights (the `relative` + absolutely positioned checkbox + `link_to` block). | S |
| **L6** | **Pagy adapter**: `ui_pagination_for(pagy, frame:)`. | Only if other 2100 apps use pagy. Otherwise keep it as the app helper in §6. | `shared/_pagination`. | S |
| **L7** | **Combobox `multiple:`/tags mode**: chips for chosen values (`ui_chip` with remove), `max:`, `allow_free_text:`, one hidden input per value. | Tag, recipient and collaborator pickers. Combobox already has the hard parts (ARIA combobox, Turbo Frame suggestions, live region). | `collaborator_select_controller.js` (226 lines). | M |
| **L8** | **Autosubmit `delay:`**: debounce `cl-autosubmit` for text inputs. | Search-as-you-type in any list. | `debounced_search_controller.js`, `filter_form_controller.js`. | S |

**Not proposed for the library** (too app-specific): platform badges, the integration card, chat bubbles, the media thumbnail logic, the template settings display.

---

## 8. Controllers that can be deleted

| App controller | Replaced by | When |
|---|---|---|
| `dropdown_controller.js` | `ui_navbar` / `ui_dropdown` (`cl-popover`) | §3.1 (fully once L1 lands) |
| `modal_controller.js` | `ui_modal` (`cl-dialog`) | §5.1, §5.2 |
| `collapse_controller.js` | `ui_accordion` / `ui_collapse` | §4 |
| `carousel_controller.js` | `ui_carousel` | §5.2 |
| `filter_form_controller.js` | `cl-autosubmit` | §5.1 |
| `debounced_search_controller.js` | `cl-autosubmit` with `delay:` | L8 |
| `bulk_select_controller.js` | `cl-bulk-select` | L3 |
| `audio_select_controller.js` | `ui_combobox` + a small listener | §5.1 |
| `collaborator_select_controller.js` | `ui_combobox multiple:` | L7 |
| `media_upload_controller.js` | `ui_file_upload direct_upload: true` (verify the folder param) | §5.2 |
| `hello_controller.js` | Delete (Rails scaffold leftover) | Now |

About 810 of the app's ~1,170 lines of Stimulus fall into this table.

---

## 9. Suggested phases

| Phase | Scope | Rough size | Exit check |
|---|---|---|---|
| 0 | Bugs B1–B8; tailwindcss-rails migration; install; indigo theme; styled confirm | 1–2 days | `bin/ci` green; every page renders identically or better; Docker image builds without Node |
| 1 | Layout: navbar (flattened until L1), flash, pagination, `PlatformBadge`/`StatusBadge` | 1 day | No `bg-indigo-600` left in `shared/` or the layout |
| 2 | Primitives sweep: buttons, badges, forms (FormBuilder), description lists, empty states, page headers, tables | 3–4 days, parallelisable by directory | `grep -r "uppercase tracking-wide" app/views` ≈ 0; `focus:ring-indigo` ≈ 0 |
| 3 | Page refactors in §5 that need no library changes (media tabs → Nav, LLM stats, sessions table, integrations card, chat model radio cards, upload → FileUpload) | 3–4 days | Controllers in §8 marked "now"/§5 deleted |
| 4 | Library additions L1–L5, then L7–L8 (release, bump, adopt) | 1–2 weeks across both repos | SMA's nav, filters and bulk select on library components |

Phase 2 is mechanical and splits cleanly by view directory, so it suits parallel agents (the `qwen-mobile-audit` / `delegate-to-qwen` skills) with a review pass per directory. Phase 4 goes through the usual library release and then `qwen-library-upgrade` to roll it out to SMA and the marketing app.
