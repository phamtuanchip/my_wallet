# App icon

- `app_icon.png` — 1024px full icon (iOS, legacy Android, store listing)
- `app_icon_fg.png` / `app_icon_bg.png` — Android adaptive icon layers

All three are rendered by `tool/make_icon.py` (Pillow):

```bash
python tool/make_icon.py assets/icon
dart run flutter_launcher_icons
```
