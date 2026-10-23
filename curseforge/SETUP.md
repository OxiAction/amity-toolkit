# CurseForge setup checklist

## 1. Create the project

CurseForge → *Create Project* → **World of Warcraft** → Addon.

| Field            | Value |
| ---------------- | ----- |
| Name             | `Amity Toolkit` |
| Summary          | `Small quality-of-life modules for WoW Forever: always-on bar text, auction iLvl, LFG role filter, Overpower alert.` |
| Description      | paste `curseforge/DESCRIPTION.md` (the editor accepts Markdown) |
| Avatar / logo    | `curseforge/logo.png` (400x400; `logo-1024.png` if a larger one is wanted) |
| Main category    | *Miscellaneous* (or *Quality of Life* if offered) |
| Extra categories | *Auction & Economy*, *Unit Frames*, *Class: Warrior*, *Combat* |
| License          | MIT (matches `LICENSE`) |
| Source           | GitHub, `https://github.com/OxiAction/amity-toolkit` |
| Issues           | `https://github.com/OxiAction/amity-toolkit/issues` |

After saving, note the **Project ID** shown in the right sidebar of the project page.

## 2. Screenshots (Images tab)

Worth adding, taken in game:

1. Player + target frames with the `100/200 50%` text
2. Auction house with the iLvl column sorted
3. LFG browse list with the role buttons
4. The Amity Toolkit panel opened from the minimap button
5. The Overpower alert (`/opa proc` simulates one)

`curseforge/banner.png` can go in the gallery as well.

## 3a. Upload manually

```powershell
powershell -ExecutionPolicy Bypass -File tools\build.ps1
```

Upload `dist\Amity-<version>.zip` under *Files → Upload File*. Choose the WoW Forever game version (Interface 16001), release type *Release*, and paste the CHANGELOG entry.

## 3b. Or release automatically from GitHub

1. Add `## X-Curse-Project-ID: <project id>` to `Amity.toc`.
2. CurseForge → profile → *API Tokens* → create a token.
3. GitHub repo → *Settings → Secrets and variables → Actions* → new secret `CF_API_KEY` with that token.
4. Release by adding a CHANGELOG entry and pushing a tag:
   ```
   git tag v1.0.0
   git push origin v1.0.0
   ```
   `.github/workflows/release.yml` builds the zip with the BigWigs packager, uploads it to CurseForge and creates a GitHub release.

The packager reads the game version from `## Interface:`. If CurseForge does not map 16001 to a game version yet, the upload fails with a game-version error. In that case, upload manually (3a) and choose the version by hand.

## Regenerating the art

```
python tools/make_art.py
```
Writes `Media/Icon.tga`, `Media/MinimapIcon.tga` and everything in `curseforge/`.
