# SoundWave Player

Reproductor de música para Android que funciona **sin internet**, con una sección de **radios online**.

## Funciones

**Música local (offline)**
- Lee toda la música del teléfono: memoria interna y tarjeta microSD.
- Biblioteca por canciones, artistas, álbumes y carpetas, con búsqueda.
- Cola de reproducción, aleatorio, repetir una o todas, siguiente y anterior.
- Sigue sonando con la pantalla apagada, con controles en la notificación, la pantalla de bloqueo y los auriculares Bluetooth.
- Recuerda la canción y la posición donde quedaste.
- Favoritas, "Agregadas recientemente" y playlists propias.
- Temporizador de apagado y ecualizador del sistema.

**Radios (necesitan internet)**
- Favoritas y recientes.
- Agregar una radio pegando su link (por ejemplo, el que copia https://flavibot.xyz/radios).
- Importar la lista de flavibot.
- Buscador de radios de todo el mundo, usando [Radio Browser](https://www.radio-browser.info).
- Botón "Radio FM" que abre la app de radio por antena del teléfono, si tiene una.

## Descargar el APK

Cada cambio en `main` compila el APK con GitHub Actions. Lo encontrás en la pestaña **Releases** del repositorio, o en **Actions → Compilar APK → Artifacts**.

En el teléfono: abrí el APK, aceptá "Instalar apps de origen desconocido" y listo.

## Compilar en la PC

Requiere Flutter 3.47.5 y Android Studio (SDK de Android).

```bash
flutter pub get
flutter build apk --release
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk`.

## Estructura

```
lib/
  main.dart                  Arranque, servicio en segundo plano y proveedores
  theme.dart                 Colores y estilo
  models/                    Song, RadioStation, Playlist
  services/
    media_library.dart       Biblioteca local (MediaStore vía MainActivity.kt)
    player_controller.dart   Reproductor, cola, temporizador, ecualizador
    database_service.dart    SQLite: radios, favoritas, playlists
    radio_sources.dart       Radios guardadas, Radio Browser, importador de flavibot
    radio_resolver.dart      Abre links .pls / .m3u para obtener el stream
  views/                     Pantallas
  widgets/                   Mini reproductor, filas de canciones, carátulas
android/app/src/main/kotlin/.../MainActivity.kt   Lectura nativa de la biblioteca de Android
```
