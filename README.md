# <img src="Preview/HeaderIcon.png" width="30" height="36" align="absmiddle" alt=""> HotAPatcher

[![Release](https://img.shields.io/github/v/release/MarkovTrue/HotAPatcher?label=Release&color=%238a2be2&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSJ3aGl0ZSIgc3Ryb2tlLXdpZHRoPSIyIiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiPjxwYXRoIGQ9Ik0xMSAyMS43M2EyIDIgMCAwIDAgMiAwbDctNEEyIDIgMCAwIDAgMjEgMTZWOGEyIDIgMCAwIDAtMS0xLjczbC03LTRhMiAyIDAgMCAwLTIgMGwtNyA0QTIgMiAwIDAgMCAzIDh2OGEyIDIgMCAwIDAgMSAxLjczeiIvPjxwYXRoIGQ9Ik0xMiAyMlYxMiIvPjxwb2x5bGluZSBwb2ludHM9IjMuMjkgNyAxMiAxMiAyMC43MSA3Ii8%2BPC9zdmc%2B)](https://github.com/MarkovTrue/HotAPatcher/releases) [![Downloads](https://img.shields.io/github/downloads/MarkovTrue/HotAPatcher/total?label=Downloads&color=%230078D4&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSJ3aGl0ZSIgc3Ryb2tlLXdpZHRoPSIyIiBzdHJva2UtbGluZWNhcD0icm91bmQiIHN0cm9rZS1saW5lam9pbj0icm91bmQiPjxwYXRoIGQ9Ik0yMSAxNXY0YTIgMiAwIDAgMS0yIDJINWEyIDIgMCAwIDEtMi0ydi00Ii8%2BPHBvbHlsaW5lIHBvaW50cz0iNyAxMCAxMiAxNSAxNyAxMCIvPjxsaW5lIHgxPSIxMiIgeDI9IjEyIiB5MT0iMTUiIHkyPSIzIi8%2BPC9zdmc%2B)](https://github.com/MarkovTrue/HotAPatcher/releases)

Утилита патчер для игры [Heroes 3: Horn of the Abyss](https://h3hota.com).

![Preview](Preview/Preview.png)

## Описание

**Подсвечивать несобранные постройки**. После патча ваши несобранные мельницы, водяные колёса, сады и склады будут мягко подсвечиваться искрами в цвет ресурса.

**Запоминать настройки новой игры**. При создании новой игры стартовые город, герой и бонус выставлены на случайные. Пропатченная игра подставляет выбор из прошлой сессии. Значение подставляется, только если оно доступно на выбранной карте. 

Выбор хранится в файле `HotA_Patcher.dat`, если его удалить, сохранение сбросится.

**Не показывать окно «Турнирные правила»**. При создании новой игры, окно появляется при каждом нажатии «Начать». Ни твики HD-мода, ни настройки игры его не отключают. Патч убирает этот лишний клик.

## Как пользоваться

1. Убедиться, что игра не запущена.
2. Запустить `HotAPatcher.exe`, желательно от имени администратора.
3. Путь к игре подставится автоматически, если она была установлена. Иначе указать папку вручную.
4. Отметить нужные галочки и нажать «Применить».
5. «Играть» закроют окно и запустит игру. 

Оригиналы перезаписываемых файлов сохраняются, отмена патча восстанавливает их.

## После обновления

Обновление HotA и HD-мода может перезаписать патченные файлы `HD_HOTA.dll`, `h3hota.exe` и `h3hota HD.exe`. В этом случае достаточно ещё раз запустить патчер.

Проверено на **HotA 1.8.1 + HD Mod 5.8**
