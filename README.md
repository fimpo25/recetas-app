# Recetas

App Android (Flutter, offline) para registrar recetas, armar el plan semanal de comidas, generar la lista de compras y calcular macro y micronutrientes.

## Descargar

Última versión para el teléfono:
**https://github.com/fimpo25/recetas-app/releases/latest/download/recetas-arm64.apk**

Abrilo desde el teléfono y permití "Instalar apps desconocidas" para el navegador la primera vez. Las versiones nuevas se instalan encima sin perder datos (todas se firman con la misma clave).

## Cómo se compila

Cada push a `main` dispara `.github/workflows/build-apk.yml`:

1. `tools/build_nutrition_db.py` descarga USDA FoodData Central (SR Legacy, dominio público) y genera `assets/db/nutrition.db` con 18 nutrientes por 100 g, porciones caseras, densidades y nombres en español (`tools/es_dictionary.py`).
2. `flutter create` genera la carpeta `android/` (no se versiona).
3. `flutter analyze` y `flutter test` (motor de cálculo en `lib/domain/`).
4. `flutter build apk --release --split-per-abi`, firmado con `ci/debug.keystore`.
5. Se publica un release `v0.1.<n>` con los APK.

## Estructura

```
lib/
  domain/     cálculo puro: unidades, nutrición, compras, metas, texto
  data/       SQLite: base nutricional (solo lectura) + base de usuario
  common/     widgets compartidos
  features/   recipes · plan · shopping · nutrition · settings
tools/        generación de la base nutricional (Python)
test/         tests del motor de cálculo
```

## Mejorar los nombres en español

Editá `tools/es_dictionary.py` (segmentos, palabras y alias de búsqueda) y hacé push: el próximo APK los incluye.

## Nota sobre la clave de firma

`ci/debug.keystore` está en el repo para que todas las compilaciones tengan la misma firma. Alcanza para uso personal; para distribuir la app conviene moverla a un secreto de GitHub.
