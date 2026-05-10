# Metal Calc APK Builder

Этот репозиторий подготовлен автоматически для сборки Flutter APK через GitHub Actions.

## Что внутри

- `.github/workflows/build-apk.yml` — workflow сборки APK.
- `source/part*.b64` — части архива с исходником приложения.

Workflow склеивает base64-части, распаковывает Flutter-проект, генерирует Android-часть командой `flutter create --platforms=android .`, затем собирает `app-release.apk` и прикрепляет его как artifact.
