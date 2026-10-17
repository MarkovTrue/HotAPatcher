; ============================================================
; Патчер для Heroes 3: Horn of the Abyss, HotA 1.8.1 + HD mod 5.8
;
; Патч 1. Убирает окно «Турнирные правила», которое HD-мод показывает
; при каждом нажатии «Начать».
;
; Патч 2. Запоминает выбранные стартовые город, героя и бонус всех игроков
; и подставляет их на следующей случайной карте.
;
; Патч 3. Подсвечивает на карте несобранные мельницы, водяные колёса,
; сады и склады: над ними поднимаются искры цвета ресурса.
;
; Все патчи трогают только файлы игры и полностью откатываются
; восстановлением резервных копий, которые патчер делает сам.
; ============================================================

#pragma compile(Out, #Build\HotAPatcher.exe)
#pragma compile(Icon, Assets\Icons\Icon.ico)
#pragma compile(ProductName, HotAPatcher)
#pragma compile(FileDescription, Патчер для Heroes 3 HotA)
#pragma compile(ProductVersion, 1.03)
#pragma compile(FileVersion, 1.03)
#pragma compile(LegalCopyright, )
#pragma compile(x64, false)

#NoTrayIcon

#include <AutoItConstants.au3>
#include <FileConstants.au3>
#include <FontConstants.au3>
#include <GDIPlus.au3>
#include <GUIConstantsEx.au3>
#include <GuiToolTip.au3>
#include <StaticConstants.au3>
#include <StringConstants.au3>
#include <WinAPIGdi.au3>
#include <WinAPISysWin.au3>
#include <WindowsConstants.au3>
#include "PatchData.au3"

Global Const $gc_sTitle = "HotAPatcher 1.03"

; Названия патчей на галочках; короткие, чтобы справа в строке влезло состояние.
; Подробности - во всплывающей подсказке
Global Const $gc_sPopupName = "Не показывать окно «Турнирные правила»"
Global Const $gc_sTownsName = "Запоминать настройки новой игры"
Global Const $gc_sMarksName = "Подсвечивать несобранные постройки"
Global Const $gc_sPopupTip = "При создании новой игры, при каждом нажатии" & @CRLF & _
		"«Начать», принудительно показывается это окно." & @CRLF & @CRLF & _
		"Патч его убирает."
Global Const $gc_sTownsTip = "При создании новой игры на случайной карте" & @CRLF & _
		"стартовые город, герой и бонус выставлены на случайные." & @CRLF & @CRLF & _
		"Патч подставляет выбор из прошлой сессии."
Global Const $gc_sMarksTip = "В игре несобранные мельницы, водяные колёса, сады" & @CRLF & _
		"и склады не отличить от собранных." & @CRLF & @CRLF & _
		"После патча над ними поднимаются искры в цвет ресурса."

Global Const $gc_sDllName = "HD_HOTA.dll"
Global Const $gc_aExeNames[2] = ["h3hota.exe", "h3hota HD.exe"]

; Не .bak: чистильщики диска выметают такие файлы заодно с мусором, а без копии
; оригинал уже не собрать. Копии прошлых версий патчер переименовывает сам
Global Const $gc_sBakExt = ".pbak"
Global Const $gc_sOldBakExt = ".bak"

; Для «получилось» и «ошибка» системных цветов нет, остальное берём у Windows
Global Const $gc_iColorOk = 0x0F7B0F
Global Const $gc_iColorBad = 0xC42B1C
Global $g_iColorText, $g_iColorMuted, $g_iColorBg, $g_iColorPanel, $g_iColorBorder

Global Const $gc_iColWidth = 392     ; ширина картинок патчей, по ней и всё окно
Global Const $gc_iPicHeight = 126
Global Const $gc_iMargin = 29        ; 8 серого поля, рамка и 20 воздуха внутри белой области
Global Const $gc_iWinWidth = $gc_iMargin * 2 + $gc_iColWidth
Global Const $gc_iInset = 8          ; серое поле слева и справа от белой области
Global Const $gc_iLineHeight = 16    ; строка состояния
Global Const $gc_iGap = 20           ; одинаковый вертикальный отступ между блоками
Global Const $gc_iMarksFrameMs = 128 ; шаг кадра картинки подсветки, как у искр в игре
Global Const $gc_iBtnWidth = 88      ; одинаковая ширина всех кнопок
Global Const $gc_iBtnHeight = 26
Global Const $gc_iBtnGap = 8         ; просвет между кнопками в ряду
Global Const $gc_iHintPad = 6        ; отступ значка подсказки от угла картинки
Global Const $gc_iTipShowMs = 10000  ; сколько висит подсказка, больше Windows не принимает
Global Const $gc_iPeHeaderSize = 0x1000   ; заголовок PE вместе с таблицей секций

; Смещения внутри заголовка PE32, всё по спецификации COFF.
; PE_* - от начала файла или заголовка PE, OPT_* - от опционального заголовка,
; ROW_* - внутри строки таблицы секций
Global Const $PE_LFANEW_AT = 0x3C          ; тут лежит смещение самого заголовка PE
Global Const $PE_SIGNATURE = 0x00004550    ; "PE\0\0"
Global Const $PE_SEC_COUNT = 6
Global Const $PE_OPT_SIZE = 20
Global Const $PE_OPT_AT = 24
Global Const $OPT_IMAGE_BASE = 28
Global Const $OPT_SEC_ALIGN = 32
Global Const $OPT_FILE_ALIGN = 36
Global Const $OPT_IMAGE_SIZE = 56
Global Const $OPT_IMPORT_DIR = 96 + 8      ; вторая запись таблицы каталогов данных
Global Const $ROW_SIZE = 40
Global Const $ROW_VSIZE = 8, $ROW_RVA = 12, $ROW_RAW_SIZE = 16, $ROW_RAW = 20
Global Const $SEC_FLAGS_CODE_RWX = 0xE0000060

; Поля строки в таблице секций, которую собирает _SectionTable
Global Const $gc_iSecName = 0, $gc_iSecRva = 1, $gc_iSecVSize = 2, $gc_iSecRaw = 3, $gc_iSecRawSize = 4

; Поля врезки в dll, которую находит _FindDllHook
Global Const $gc_iHookAt = 0, $gc_iHookRva = 1, $gc_iHookContinue = 2, $gc_iHookCall = 3

Global $g_hGui
Global $g_idInput, $g_idBrowse, $g_idApply, $g_idPlay, $g_idCancel, $g_idPopup, $g_idTowns, $g_idMarks
Global $g_idPopupState, $g_idTownsState, $g_idMarksState, $g_idPathState
; Что реально установлено в игре сейчас
Global $g_bPopupOn = False, $g_bTownsOn = False, $g_bMarksOn = False
; Патч стоял и был снят на наших глазах: пометка живёт до конца работы патчера
; и только для той папки, в которой мы его снимали
Global $g_bPopupOff = False, $g_bTownsOff = False, $g_bMarksOff = False, $g_sOffDir = ""
Global $g_sLastDir = "", $g_sAutoDir = ""
Global $g_ahBitmaps[2] = [0, 0]
Global $g_hHintImage = 0   ; значок подсказки, GDI+ держит его только пока строится окно
; Кадры картинки подсветки: static-контрол GIF не проигрывает, их листает таймер
Global $g_idMarksPic, $g_ahMarksFrames[0], $g_iMarksFrame = 0

; Окно поднимается только при обычном запуске: Tools\TestPatches.au3 подключает
; этот файл как библиотеку, и _Main() ему не нужен
If @Compiled Or @ScriptName = "HotAPatcher.au3" Then _Main()

Func _Main()
	If Not @Compiled Then FileChangeDir(@ScriptDir)
	OnAutoItExitRegister("_Cleanup")   ; временные файлы и кадры убираем при любом выходе

	_InitColors()
	_BuildGui()

	Local $sStart = _DetectGameDir()
	If $sStart <> "" Then GUICtrlSetData($g_idInput, $sStart)
	_RefreshState()
	GUISetState(@SW_SHOW, $g_hGui)   ; показываем уже готовое окно

	While True
		Switch GUIGetMsg()
			Case $GUI_EVENT_CLOSE
				ExitLoop

			Case $g_idBrowse
				_BrowseForDir()

			Case $g_idMarks, $g_idPopup, $g_idTowns
				_UpdateButtons()

			Case $g_idApply
				_DoApply()

			Case $g_idPlay
				If _LaunchGame() Then ExitLoop

			Case $g_idCancel
				ExitLoop

			Case Else
				If GUICtrlRead($g_idInput) <> $g_sLastDir Then _RefreshState()
		EndSwitch
	WEnd
EndFunc   ;==>_Main


; ==========================================================
; Интерфейс
; ==========================================================

Func _InitColors()
	$g_iColorText = _SysColor($COLOR_WINDOWTEXT)
	$g_iColorMuted = _SysColor($COLOR_GRAYTEXT)
	$g_iColorBg = _SysColor($COLOR_BTNFACE)      ; фон окна, как в системных диалогах
	$g_iColorPanel = _SysColor($COLOR_WINDOW)    ; рабочая область
	$g_iColorBorder = _SysColor($COLOR_3DSHADOW) ; её рамка
EndFunc   ;==>_InitColors


; GetSysColor отдаёт COLORREF, то есть BGR, а GUICtrlSet* ждут RGB
Func _SysColor($iIndex)
	Return _WinAPI_SwitchColor(_WinAPI_GetSysColor($iIndex))
EndFunc   ;==>_SysColor


Func _BuildGui()
	$g_hGui = GUICreate($gc_sTitle, $gc_iWinWidth, 100)   ; высоту подгоняем в конце
	GUISetBkColor($g_iColorBg)
	GUISetFont(9, $FW_NORMAL, 0, "Segoe UI")
	_SetWindowIcon()
	_GDIPlus_Startup()

	; Шапки нет: серое поле сверху такое же, как по бокам
	Local $iPanelTop = $gc_iInset

	; Дальше идём сверху вниз, отступ между блоками всегда одинаковый
	Local $iX = $gc_iMargin
	Local $iPicTop = 26   ; галочка со строкой состояния над картинкой
	Local $iY = $iPanelTop + 1 + $gc_iGap

	_LoadHintImage()   ; значок подсказки впекается в картинки патчей

	$g_idMarks = _CreatePatch($iX, $iY, $gc_sMarksName, $gc_sMarksTip, $g_idMarksState)
	$g_idMarksPic = _CreatePatchPic($iX, $iY + $iPicTop, $gc_sMarksTip)
	_LoadMarksFrames()
	$iY += $iPicTop + $gc_iPicHeight + $gc_iGap

	$g_idTowns = _CreatePatch($iX, $iY, $gc_sTownsName, $gc_sTownsTip, $g_idTownsState)
	$g_ahBitmaps[1] = _LoadPicture(_CreatePatchPic($iX, $iY + $iPicTop, $gc_sTownsTip), "Towns.png")
	$iY += $iPicTop + $gc_iPicHeight + $gc_iGap

	$g_idPopup = _CreatePatch($iX, $iY, $gc_sPopupName, $gc_sPopupTip, $g_idPopupState)
	$g_ahBitmaps[0] = _LoadPicture(_CreatePatchPic($iX, $iY + $iPicTop, $gc_sPopupTip), "Popup.png")
	$iY += $iPicTop + $gc_iPicHeight + $gc_iGap

	_FreeHintImage()

	Local $idPathLabel = GUICtrlCreateLabel("Папка с игрой", $iX, $iY, 300, 16)
	GUICtrlSetColor($idPathLabel, $g_iColorText)
	GUICtrlSetBkColor($idPathLabel, $g_iColorPanel)
	$iY += 20

	$g_idInput = GUICtrlCreateInput("", $iX, $iY, $gc_iColWidth - $gc_iBtnWidth - 8, 24)
	$g_idBrowse = GUICtrlCreateButton("Обзор...", $iX + $gc_iColWidth - $gc_iBtnWidth, $iY - 1, _
			$gc_iBtnWidth, $gc_iBtnHeight)
	$iY += 28

	$g_idPathState = GUICtrlCreateLabel("", $iX, $iY, $gc_iColWidth, $gc_iLineHeight)
	GUICtrlSetBkColor($g_idPathState, $g_iColorPanel)
	$iY += $gc_iLineHeight + $gc_iGap

	; Кнопки справа налево: «Применить», «Играть», «Закрыть»
	Local $iPanelBottom = $iY
	Local $iRight = $gc_iWinWidth - $gc_iInset - 1
	Local $iButtons = $iPanelBottom + 12
	Local $iStep = $gc_iBtnWidth + $gc_iBtnGap
	$g_idApply = GUICtrlCreateButton("Применить", $iRight - $gc_iBtnWidth, $iButtons, _
			$gc_iBtnWidth, $gc_iBtnHeight)
	$g_idPlay = GUICtrlCreateButton("Играть", $iRight - $gc_iBtnWidth - $iStep, $iButtons, _
			$gc_iBtnWidth, $gc_iBtnHeight)
	$g_idCancel = GUICtrlCreateButton("Закрыть", $iRight - $gc_iBtnWidth - $iStep * 2, $iButtons, _
			$gc_iBtnWidth, $gc_iBtnHeight)

	; Белое поле создаётся раньше рамки: тогда рамка лежит ниже него
	; и с WS_CLIPSIBLINGS рисует только выступающий по краю контур
	Local $iFrame = $gc_iInset, $iPanelHeight = $iPanelBottom - $iPanelTop
	_Backdrop(GUICtrlCreateLabel("", $iFrame + 1, $iPanelTop + 1, _
			$gc_iWinWidth - ($iFrame + 1) * 2, $iPanelHeight - 2), $g_iColorPanel)
	_Backdrop(GUICtrlCreateLabel("", $iFrame, $iPanelTop, $gc_iWinWidth - $iFrame * 2, $iPanelHeight), $g_iColorBorder)

	_GDIPlus_Shutdown()
	_FitWindow($iButtons + $gc_iBtnHeight + 12)
EndFunc   ;==>_BuildGui


; Высота окна считается по разметке: иначе её приходится править руками
; после каждого изменения содержимого
Func _FitWindow($iContentHeight)
	Local $aWin = WinGetPos($g_hGui)
	Local $aClient = WinGetClientSize($g_hGui)
	Local $iHeight = $iContentHeight + $aWin[3] - $aClient[1]   ; плюс заголовок и рамка
	WinMove($g_hGui, "", (@DesktopWidth - $aWin[2]) / 2, (@DesktopHeight - $iHeight) / 2, $aWin[2], $iHeight)
EndFunc   ;==>_FitWindow


; Галочка патча и строка состояния справа в той же строке;
; ширину между ними делит _FitPatchRow по тексту состояния
Func _CreatePatch($iX, $iY, $sName, $sTip, ByRef $idState)
	Local Const $SS_ENDELLIPSIS = 0x4000   ; в StaticConstants его нет

	Local $idCheck = GUICtrlCreateCheckbox(" " & $sName, $iX, $iY, $gc_iColWidth, 20)
	GUICtrlSetColor($idCheck, $g_iColorText)
	GUICtrlSetBkColor($idCheck, $g_iColorPanel)
	_SetTip($idCheck, $sTip)
	$idState = GUICtrlCreateLabel("", $iX + $gc_iColWidth, $iY + 2, 0, $gc_iLineHeight, _
			BitOR($SS_RIGHT, $SS_ENDELLIPSIS))
	GUICtrlSetBkColor($idState, $g_iColorPanel)
	Return $idCheck
EndFunc   ;==>_CreatePatch


; Картинка патча с той же подсказкой, что у галочки: на подсказку намекает
; значок в углу картинки и курсор-лапа
Func _CreatePatchPic($iX, $iY, $sTip)
	Local $idPic = GUICtrlCreatePic("", $iX, $iY, $gc_iColWidth, $gc_iPicHeight)
	_SetTip($idPic, $sTip)
	GUICtrlSetCursor($idPic, $MCID_HAND)   ; лапа - 0, а 16 это $MCID_NONE: курсор пропадал
	Return $idPic
EndFunc   ;==>_CreatePatchPic


Func _SetState($idLabel, $sText, $iColor, $sTip = "")
	GUICtrlSetData($idLabel, $sText)
	GUICtrlSetColor($idLabel, $iColor)
	Local $idCheck = _PatchCheckOf($idLabel)
	If $idCheck Then _FitPatchRow($idCheck, $idLabel, $sText, $sTip)
EndFunc   ;==>_SetState


; Галочка, в строке которой стоит это состояние; 0 - строка под путём
Func _PatchCheckOf($idState)
	Switch $idState
		Case $g_idPopupState
			Return $g_idPopup
		Case $g_idTownsState
			Return $g_idTowns
		Case $g_idMarksState
			Return $g_idMarks
	EndSwitch
	Return 0
EndFunc   ;==>_PatchCheckOf


; Состояние прижато вправо и забирает у галочки столько места, сколько ему нужно:
; длинная ошибка важнее названия патча. Не влезло и так - многоточие, а полный
; текст в подсказке, если своей подсказки у состояния нет
Func _FitPatchRow($idCheck, $idState, $sText, $sTip)
	Local Const $CHECK_BOX = 18, $GAP = 8   ; квадратик галочки с отступом, просвет до состояния
	Local $iMax = $gc_iColWidth - $CHECK_BOX - $GAP
	Local $iWidth = ($sText = "") ? 0 : _TextWidth($idState, $sText) + 2
	If $iWidth > $iMax Then $iWidth = $iMax
	If $sTip = "" And $iWidth = $iMax Then $sTip = $sText

	Local $aPos = ControlGetPos($g_hGui, "", $idCheck)
	GUICtrlSetPos($idCheck, $gc_iMargin, $aPos[1], $gc_iColWidth - $iWidth - $GAP, $aPos[3])
	GUICtrlSetPos($idState, $gc_iMargin + $gc_iColWidth - $iWidth, $aPos[1] + 2, $iWidth, $gc_iLineHeight)
	_SetTip($idState, $sTip)
	GUICtrlSetCursor($idState, ($sTip = "") ? -1 : $MCID_HELP)   ; -1 - курсор по умолчанию
EndFunc   ;==>_FitPatchRow


; Штатно подсказка гаснет через 5 секунд, текст не успеть прочитать.
; AutoIt пересоздаёт окно подсказки на каждый вызов, и задержка
; сбрасывается: ставим её заново всем окнам подсказок патчера
Func _SetTip($idCtrl, $sTip)
	GUICtrlSetTip($idCtrl, $sTip)
	Local $aTips = WinList("[CLASS:tooltips_class32]")
	For $i = 1 To $aTips[0][0]
		If WinGetProcess($aTips[$i][1]) = @AutoItPID Then _
				_GUIToolTip_SetDelayTime($aTips[$i][1], $TTDT_AUTOPOP, $gc_iTipShowMs)
	Next
EndFunc   ;==>_SetTip


; Ширина текста в пикселях шрифтом контрола
Func _TextWidth($idCtrl, $sText)
	Local $hCtrl = GUICtrlGetHandle($idCtrl)
	Local $hDC = _WinAPI_GetDC($hCtrl)
	Local $hOld = _WinAPI_SelectObject($hDC, GUICtrlSendMsg($idCtrl, $WM_GETFONT, 0, 0))
	Local $tSize = _WinAPI_GetTextExtentPoint32($hDC, $sText)
	_WinAPI_SelectObject($hDC, $hOld)
	_WinAPI_ReleaseDC($hCtrl, $hDC)
	Return DllStructGetData($tSize, "X")
EndFunc   ;==>_TextWidth


; Красит подложку. WS_CLIPSIBLINGS - чтобы при перерисовке она не затирала
; соседей: без него у полей пропадали рамки, а картинки исчезали.
; SS_NOTIFY снимаем, иначе мышь не проваливается сквозь подложку
Func _Backdrop($idCtrl, $iColor)
	GUICtrlSetBkColor($idCtrl, $iColor)
	Local $hCtrl = GUICtrlGetHandle($idCtrl)
	Local $iStyle = _WinAPI_GetWindowLong($hCtrl, $GWL_STYLE)
	$iStyle = BitOR(BitAND($iStyle, BitNOT($SS_NOTIFY)), $WS_CLIPSIBLINGS)
	_WinAPI_SetWindowLong($hCtrl, $GWL_STYLE, $iStyle)
EndFunc   ;==>_Backdrop


Func _SetWindowIcon()
	Local $sIco = @TempDir & "\HotaPatcher_game.ico"
	FileInstall("Assets\Icons\Icon.ico", $sIco, $FC_OVERWRITE)
	If FileExists($sIco) Then GUISetIcon($sIco, 0, $g_hGui)
EndFunc   ;==>_SetWindowIcon


; FileInstall требует литерал в обоих аргументах, поэтому перечисление,
; а не имя переменной
Func _LoadPicture($idPic, $sName)
	Local $sPath = @TempDir & "\HotaPatcher_" & $sName
	Switch $sName
		Case "Popup.png"
			FileInstall("Assets\Popup.png", $sPath, $FC_OVERWRITE)
		Case "Towns.png"
			FileInstall("Assets\Towns.png", $sPath, $FC_OVERWRITE)
	EndSwitch
	If Not FileExists($sPath) Then Return 0

	Local $hImage = _GDIPlus_ImageLoadFromFile($sPath)
	Local $hBitmap = 0
	If $hImage Then
		$hBitmap = _HintedBitmap($hImage)
		_GDIPlus_ImageDispose($hImage)
	EndIf
	FileDelete($sPath)
	If Not $hBitmap Then Return 0

	Local $hPrevious = GUICtrlSendMsg($idPic, $STM_SETIMAGE, $IMAGE_BITMAP, $hBitmap)
	If $hPrevious Then _WinAPI_DeleteObject($hPrevious)
	Return $hBitmap
EndFunc   ;==>_LoadPicture


Func _LoadHintImage()
	Local $sPath = @TempDir & "\HotaPatcher_Hint.png"
	FileInstall("Assets\Hint.png", $sPath, $FC_OVERWRITE)
	$g_hHintImage = _GDIPlus_ImageLoadFromFile($sPath)
	If @error Then $g_hHintImage = 0   ; картинки останутся без значка, подсказка всё равно работает
EndFunc   ;==>_LoadHintImage


Func _FreeHintImage()
	If $g_hHintImage Then _GDIPlus_ImageDispose($g_hHintImage)
	$g_hHintImage = 0
	FileDelete(@TempDir & "\HotaPatcher_Hint.png")   ; GDI+ держит файл открытым, пока картинка жива
EndFunc   ;==>_FreeHintImage


; Картинка со значком подсказки в правом верхнем углу, в HBITMAP на цвет фона.
; Рисуем на своём холсте: у PNG с палитрой GDI+ не даёт контекст рисования,
; а кадры GIF копятся на общем холсте, и значок на нём темнел бы с каждым кадром
Func _HintedBitmap($hImage)
	Local $iWidth = _GDIPlus_ImageGetWidth($hImage), $iHeight = _GDIPlus_ImageGetHeight($hImage)
	Local $hCanvas = _GDIPlus_BitmapCreateFromScan0($iWidth, $iHeight)
	Local $hGraphics = _GDIPlus_ImageGetGraphicsContext($hCanvas)
	_GDIPlus_GraphicsDrawImageRect($hGraphics, $hImage, 0, 0, $iWidth, $iHeight)
	If $g_hHintImage Then
		Local $iHint = _GDIPlus_ImageGetWidth($g_hHintImage)
		_GDIPlus_GraphicsDrawImageRect($hGraphics, $g_hHintImage, $iWidth - $iHint - $gc_iHintPad, $gc_iHintPad, _
				$iHint, $iHint)
	EndIf
	_GDIPlus_GraphicsDispose($hGraphics)

	; Альфа-канал PNG блендим в цвет фона окна, иначе GDI+ зальёт его чёрным
	Local $hBitmap = _GDIPlus_BitmapCreateHBITMAPFromBitmap($hCanvas, BitOR(0xFF000000, $g_iColorBg))
	_GDIPlus_BitmapDispose($hCanvas)
	Return $hBitmap
EndFunc   ;==>_HintedBitmap


; Кадры анимированной картинки подсветки - в HBITMAP на цвет фона, и таймер
; на их смену. Кадры в GIF хранят только изменившиеся пиксели, поэтому каждый
; рисуется поверх предыдущего на общем холсте
Func _LoadMarksFrames()
	Local $sPath = @TempDir & "\HotaPatcher_Marks.gif"
	FileInstall("Assets\Marks.gif", $sPath, $FC_OVERWRITE)
	Local $hImage = _GDIPlus_ImageLoadFromFile($sPath)
	If Not $hImage Then
		FileDelete($sPath)
		Return
	EndIf

	Local $iCount = _GDIPlus_ImageGetFrameCount($hImage, $GDIP_FRAMEDIMENSION_TIME)
	Local $iWidth = _GDIPlus_ImageGetWidth($hImage), $iHeight = _GDIPlus_ImageGetHeight($hImage)
	Local $hCanvas = _GDIPlus_BitmapCreateFromScan0($iWidth, $iHeight)
	Local $hGraphics = _GDIPlus_ImageGetGraphicsContext($hCanvas)
	ReDim $g_ahMarksFrames[$iCount]
	For $i = 0 To $iCount - 1
		_GDIPlus_ImageSelectActiveFrame($hImage, $GDIP_FRAMEDIMENSION_TIME, $i)
		_GDIPlus_GraphicsDrawImageRect($hGraphics, $hImage, 0, 0, $iWidth, $iHeight)
		$g_ahMarksFrames[$i] = _HintedBitmap($hCanvas)
	Next
	_GDIPlus_GraphicsDispose($hGraphics)
	_GDIPlus_BitmapDispose($hCanvas)
	_GDIPlus_ImageDispose($hImage)
	FileDelete($sPath)   ; GDI+ держит файл открытым, пока картинка жива

	If $iCount = 0 Then Return
	$g_iMarksFrame = -1
	_NextMarksFrame()
	AdlibRegister("_NextMarksFrame", $gc_iMarksFrameMs)
EndFunc   ;==>_LoadMarksFrames


; Static-контрол хранит копию картинки, если в ней есть альфа, и отдаёт её
; при следующей смене. Чужую копию удаляем, свои кадры живут до выхода
Func _NextMarksFrame()
	Local $iCount = UBound($g_ahMarksFrames)
	If $iCount = 0 Then Return
	$g_iMarksFrame = Mod($g_iMarksFrame + 1, $iCount)
	Local $hPrevious = GUICtrlSendMsg($g_idMarksPic, $STM_SETIMAGE, $IMAGE_BITMAP, $g_ahMarksFrames[$g_iMarksFrame])
	If $hPrevious = 0 Then Return
	For $i = 0 To $iCount - 1
		If $g_ahMarksFrames[$i] = $hPrevious Then Return
	Next
	_WinAPI_DeleteObject($hPrevious)
EndFunc   ;==>_NextMarksFrame


Func _Cleanup()
	AdlibUnRegister("_NextMarksFrame")
	For $i = 0 To UBound($g_ahMarksFrames) - 1
		_WinAPI_DeleteObject($g_ahMarksFrames[$i])
	Next
	For $i = 0 To UBound($g_ahBitmaps) - 1
		If $g_ahBitmaps[$i] Then _WinAPI_DeleteObject($g_ahBitmaps[$i])
	Next
	FileDelete(@TempDir & "\HotaPatcher_game.ico")
EndFunc   ;==>_Cleanup


; ==========================================================
; Поиск папки
; ==========================================================

Func _DetectGameDir()
	Local $sDir = _RegistryGameDir()
	If _DirIsGame($sDir) Then
		$g_sAutoDir = $sDir   ; запомнили, чтобы написать, откуда она взялась
		Return $sDir
	EndIf

	If _DirIsGame(@ScriptDir) Then Return @ScriptDir
	Return ""
EndFunc   ;==>_DetectGameDir


Func _RegistryGameDir()
	; Обе разрядности: HKLM64 для x86-процесса, WOW6432Node для x64-процесса
	Local $aRoots[4] = [ _
			"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", _
			"HKLM64\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", _
			"HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall", _
			"HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"]

	For $i = 0 To UBound($aRoots) - 1
		Local $iIndex = 1
		While True
			Local $sKey = RegEnumKey($aRoots[$i], $iIndex)
			If @error Then ExitLoop
			$iIndex += 1
			Local $sFullKey = $aRoots[$i] & "\" & $sKey
			Local $sName = RegRead($sFullKey, "DisplayName")
			If StringInStr($sName, "Abyss") = 0 And StringInStr($sKey, "HotA") = 0 Then ContinueLoop
			Local $sDir = RegRead($sFullKey, "InstallLocation")
			If $sDir = "" Then $sDir = RegRead($sFullKey, "Inno Setup: App Path")
			$sDir = _TrimSlash($sDir)
			If _DirIsGame($sDir) Then Return $sDir
		WEnd
	Next
	Return ""
EndFunc   ;==>_RegistryGameDir


Func _BrowseForDir()
	Local $sCurrent = GUICtrlRead($g_idInput)
	If Not FileExists($sCurrent) Then $sCurrent = ""
	Local $sDir = FileSelectFolder("Укажите папку с установленной игрой Heroes 3 HotA", "", 0, $sCurrent)
	If @error Then Return
	GUICtrlSetData($g_idInput, _TrimSlash($sDir))
	_RefreshState()
EndFunc   ;==>_BrowseForDir


; Папка годится, только если на месте все три файла, которые мы правим
Func _DirIsGame($sDir)
	If $sDir = "" Then Return False
	Local $aFiles = _TargetFiles($sDir)
	For $i = 0 To UBound($aFiles) - 1
		If Not FileExists($aFiles[$i]) Then Return False
	Next
	Return True
EndFunc   ;==>_DirIsGame


Func _GameDir()
	Return StringStripWS(GUICtrlRead($g_idInput), $STR_STRIPLEADING + $STR_STRIPTRAILING)
EndFunc   ;==>_GameDir


; ==========================================================
; Состояние GUI
; ==========================================================

Func _RefreshState()
	Local $sDir = _GameDir()
	$g_sLastDir = GUICtrlRead($g_idInput)

	If Not _DirIsGame($sDir) Then
		_SetState($g_idPathState, "В указанной папке нет файлов игры", $gc_iColorBad)
		_ShowPatches(False, False, False)   ; не знаем состояния - не показываем и галочек
		_SetState($g_idPopupState, "", $g_iColorMuted)
		_SetState($g_idTownsState, "", $g_iColorMuted)
		_SetState($g_idMarksState, "", $g_iColorMuted)
		_UpdateButtons()
		Return
	EndIf

	If $sDir = $g_sAutoDir Then
		_SetState($g_idPathState, "Путь найден в реестре установленных программ", $g_iColorMuted)
	Else
		_SetState($g_idPathState, "Файлы игры на месте", $g_iColorMuted)
	EndIf

	Local $aOn = _InstalledPatches($sDir)
	_ShowPatches($aOn[0], $aOn[1], $aOn[2])
	_UpdateButtons()
EndFunc   ;==>_RefreshState


; Что стоит в файлах игры: [окно, настройки, подсветка]. Dll читается и
; просматривается один раз на оба своих патча: это самая дорогая часть опроса,
; а место врезки в ней для обоих одно и то же
Func _InstalledPatches($sDir)
	Local $aOn[3] = [False, False, _ExeProblem($sDir, True) = ""]
	Local $sDll = _ReadFileHex($sDir & "\" & $gc_sDllName)
	If @error Then Return $aOn
	Local $aHook = _FindDllHook($sDll)
	If @error Then Return $aOn
	$aOn[0] = _PopupPatchedAt($sDll, $aHook)
	$aOn[1] = _ExeProblem($sDir, False) = "" And _DllStubStateAt($sDll, $aHook) = ""
	Return $aOn
EndFunc   ;==>_InstalledPatches


; Галочки и строки под ними всегда показывают то, что лежит в файлах игры
Func _ShowPatches($bPopup, $bTowns, $bMarks)
	_MarkRemoved(_GameDir(), $bPopup, $bTowns, $bMarks)
	$g_bPopupOn = $bPopup
	$g_bTownsOn = $bTowns
	$g_bMarksOn = $bMarks
	GUICtrlSetState($g_idPopup, $bPopup ? $GUI_CHECKED : $GUI_UNCHECKED)
	GUICtrlSetState($g_idTowns, $bTowns ? $GUI_CHECKED : $GUI_UNCHECKED)
	GUICtrlSetState($g_idMarks, $bMarks ? $GUI_CHECKED : $GUI_UNCHECKED)
	_ShowPatchState($g_idPopupState, $bPopup, $g_bPopupOff)
	_ShowPatchState($g_idTownsState, $bTowns, $g_bTownsOff)
	_ShowPatchState($g_idMarksState, $bMarks, $g_bMarksOff)
EndFunc   ;==>_ShowPatches


; Отмечает патчи, пропавшие из файлов на наших глазах: только их и зовём
; «снятыми». Пометки привязаны к папке, в другой игре они ничего не значат
Func _MarkRemoved($sDir, $bPopup, $bTowns, $bMarks)
	If $sDir <> $g_sOffDir Then
		$g_sOffDir = $sDir
		$g_bPopupOff = False
		$g_bTownsOff = False
		$g_bMarksOff = False
	EndIf

	If $bMarks Then
		$g_bMarksOff = False
	ElseIf $g_bMarksOn Then
		$g_bMarksOff = True
	EndIf

	If $bPopup Then
		$g_bPopupOff = False
	ElseIf $g_bPopupOn Then
		$g_bPopupOff = True
	EndIf

	If $bTowns Then
		$g_bTownsOff = False
	ElseIf $g_bTownsOn Then
		$g_bTownsOff = True
	EndIf
EndFunc   ;==>_MarkRemoved


Func _ShowPatchState($idLabel, $bOn, $bOff)
	If $bOn Then
		_SetState($idLabel, "✓  Патч установлен", $gc_iColorOk)
	ElseIf $bOff Then
		_SetState($idLabel, "Патч снят", $g_iColorMuted)
	Else
		_SetState($idLabel, "Патч не установлен", $g_iColorMuted)
	EndIf
EndFunc   ;==>_ShowPatchState


; «Применить» доступна, только если отмеченное расходится с установленным
Func _UpdateButtons()
	Local $bChanged = (GUICtrlRead($g_idPopup) = $GUI_CHECKED) <> $g_bPopupOn Or _
			(GUICtrlRead($g_idTowns) = $GUI_CHECKED) <> $g_bTownsOn Or _
			(GUICtrlRead($g_idMarks) = $GUI_CHECKED) <> $g_bMarksOn

	If _DirIsGame(_GameDir()) And $bChanged Then
		GUICtrlSetState($g_idApply, $GUI_ENABLE)
	Else
		GUICtrlSetState($g_idApply, $GUI_DISABLE)
	EndIf
EndFunc   ;==>_UpdateButtons


; ==========================================================
; Действия
; ==========================================================

; Приводит файлы игры к тому состоянию, которое отмечено галочками
Func _DoApply()
	Local $sDir = _GameDir()
	Local $bPopup = (GUICtrlRead($g_idPopup) = $GUI_CHECKED)
	Local $bTowns = (GUICtrlRead($g_idTowns) = $GUI_CHECKED)
	Local $bMarks = (GUICtrlRead($g_idMarks) = $GUI_CHECKED)
	Local $bPopupChanged = ($bPopup <> $g_bPopupOn)
	Local $bTownsChanged = ($bTowns <> $g_bTownsOn)
	Local $bMarksChanged = ($bMarks <> $g_bMarksOn)

	_Busy(True)   ; патч занимает около полусекунды, и всё это время окно молчит

	Local $sError = "", $sShort = ""
	If _GameIsRunning() Then
		$sShort = "Файлы заняты, закройте игру"
		$sError = $sShort
	Else
		$sError = _ApplyPatches($sDir, $bPopup, $bTowns, $bMarks)
		If $sError <> "" Then _RestoreFromBackups($sDir)   ; не оставляем файлы на полпути
	EndIf

	_RefreshState()   ; строки состояния пересчитываются по самим файлам игры
	_Busy(False)

	; Галочки могли остаться неотработанными и без явной ошибки: патч мог лечь
	; наполовину, поэтому итог сверяется с тем, что просили
	If $sError = "" And ($g_bPopupOn <> $bPopup Or $g_bTownsOn <> $bTowns Or $g_bMarksOn <> $bMarks) Then _
			$sError = _Mismatch($sDir, $bPopup, $bTowns, $bMarks)

	; После полного отката файлы снова оригинальные, копии хранить незачем
	If $sError = "" And Not $g_bPopupOn And Not $g_bTownsOn And Not $g_bMarksOn Then _DeleteBackups($sDir)

	; Об ошибке пишем там, где пользователь ждал изменения: коротко, подробности в подсказке
	If $sError <> "" Then
		If $sShort = "" Then $sShort = _ShortError($sError)
		Local $sTip = ($sShort = $sError) ? "" : $sError
		If $bPopupChanged Then _SetState($g_idPopupState, $sShort, $gc_iColorBad, $sTip)
		If $bTownsChanged Then _SetState($g_idTownsState, $sShort, $gc_iColorBad, $sTip)
		If $bMarksChanged Then _SetState($g_idMarksState, $sShort, $gc_iColorBad, $sTip)
	EndIf
EndFunc   ;==>_DoApply


; Короткая ошибка для строки патча. Сбои чтения, записи и копий начинаются
; с «Не удалось» и «Потеряна», а патч, оставшийся после отката, говорит «остал...».
; Всё прочее значит, что патчер не узнал код игры: у неё другая версия
Func _ShortError($sError)
	If StringRegExp($sError, "(?i)^(не удалось (прочитать|записать|создать|восстановить)|потеряна)|остал") Then _
			Return "Не удалось изменить файлы игры"
	Return "Не подходит для этой версии игры"
EndFunc   ;==>_ShortError


; Курсор ожидания на время работы с файлами. Перерисовываем сразу: очередь
; сообщений патчер не качает, пока правит файлы, и нажатая кнопка осталась бы
; обычной. «Играть» гасим тоже: клик дошёл бы до полупропатченных файлов
Func _Busy($bOn)
	GUICtrlSetState($g_idPlay, $bOn ? $GUI_DISABLE : $GUI_ENABLE)
	If Not $bOn Then
		GUISetCursor($MCID_ARROW, 0, $g_hGui)   ; «Применить» вернёт _UpdateButtons, если есть что применять
		Return
	EndIf
	GUICtrlSetState($g_idApply, $GUI_DISABLE)
	GUISetCursor($MCID_WAIT, 1, $g_hGui)
	_WinAPI_RedrawWindow($g_hGui, 0, 0, BitOR($RDW_ALLCHILDREN, $RDW_UPDATENOW))
EndFunc   ;==>_Busy


; Запускает игру через лаунчер HD-мода: обычные ярлыки ведут туда же.
; False - запустить не вышло, причина написана в строке под путём
Func _LaunchGame()
	Local $sDir = _GameDir()
	Local $sExe = $sDir & "\" & $gc_aExeNames[1]

	If FileExists($sExe) Then
		Run('"' & $sExe & '"', $sDir)
		If Not @error Then Return True
	EndIf

	_SetState($g_idPathState, "Не удалось запустить " & $gc_aExeNames[1], $gc_iColorBad)
	Return False
EndFunc   ;==>_LaunchGame


; Правит файлы игры; возвращает описание ошибки или пустую строку
Func _ApplyPatches($sDir, $bPopup, $bTowns, $bMarks)
	_MigrateBackups($sDir)   ; копии от прошлых версий лежат под старым расширением

	If Not $bPopup And Not $bTowns And Not $bMarks Then Return _RestoreFromBackups($sDir, True)

	Local $sError = _EnsureBackups($sDir)
	If $sError <> "" Then Return $sError
	$sError = _RestoreFromBackups($sDir)   ; патчим всегда от оригиналов
	If $sError <> "" Then Return $sError

	For $i = 0 To UBound($gc_aExeNames) - 1
		$sError = _PatchExeFile($sDir & "\" & $gc_aExeNames[$i], $bTowns, $bMarks)
		If $sError <> "" Then Return $sError
	Next
	If Not $bPopup And Not $bTowns Then Return ""

	; Заглушка в dll зовёт процедуру из секции exe, поэтому её адрес
	; берётся из уже пропатченного файла
	Local $iSave = 0
	If $bTowns Then
		$iSave = _ExeSaveProc($sDir & "\" & $gc_aExeNames[1])
		If $iSave = 0 Then Return "В " & $gc_aExeNames[1] & " не нашлась секция патча"
	EndIf
	Return _PatchDll($sDir & "\" & $gc_sDllName, $bPopup, $iSave)
EndFunc   ;==>_ApplyPatches


; Называет, что именно разошлось с запрошенным. Патч мог лечь наполовину:
; секция добавилась, а врезка не встала - тогда причина видна по самим файлам
Func _Mismatch($sDir, $bPopup, $bTowns, $bMarks)
	If $bMarks <> $g_bMarksOn Then
		If Not $bMarks Then Return "подсветка осталась в файлах игры"
		Local $sMarks = _ExeProblem($sDir, True)
		If $sMarks = "" Then $sMarks = "причина не видна"
		Return "подсветка не встала, " & $sMarks
	EndIf

	If $bTowns <> $g_bTownsOn Then
		If Not $bTowns Then Return "патч настроек остался в файлах игры"
		Local $sWhy = _ExeProblem($sDir, False)
		If $sWhy = "" Then $sWhy = _DllStubState($sDir & "\" & $gc_sDllName)
		If $sWhy = "" Then $sWhy = "причина не видна"
		Return "патч настроек не встал, " & $sWhy
	EndIf
	If Not $bPopup Then Return "патч окна остался в файлах игры"
	Return "патч окна не встал, окно всё так же показывается"
EndFunc   ;==>_Mismatch


; ==========================================================
; Резервные копии
; ==========================================================

Func _TargetFiles($sDir)
	Local $aFiles[3] = [$sDir & "\" & $gc_sDllName, $sDir & "\" & $gc_aExeNames[0], $sDir & "\" & $gc_aExeNames[1]]
	Return $aFiles
EndFunc   ;==>_TargetFiles


Func _BakPath($sPath)
	Return $sPath & $gc_sBakExt
EndFunc   ;==>_BakPath


; Подбирает копии прошлых версий под новым расширением, пока они целы.
; Если новая копия уже есть, старую не трогаем: вдруг она и есть оригинал
Func _MigrateBackups($sDir)
	Local $aFiles = _TargetFiles($sDir)
	For $i = 0 To UBound($aFiles) - 1
		Local $sOld = $aFiles[$i] & $gc_sOldBakExt
		If FileExists($sOld) And Not FileExists(_BakPath($aFiles[$i])) Then _
				FileMove($sOld, _BakPath($aFiles[$i]))
	Next
EndFunc   ;==>_MigrateBackups


; Несёт ли файл наш патч. Своя секция - главная метка, но патч окна обходится
; без неё, поэтому у dll смотрим ещё и саму врезку
Func _FilePatched($sPath)
	Local $sHead = _ReadBytes($sPath, 0, $gc_iPeHeaderSize)
	If @error Then Return False
	If _SectionRawByName($sHead, ".hpatch") <> 0 Or _SectionRawByName($sHead, ".hmark") <> 0 Then Return True
	If StringRight($sPath, StringLen($gc_sDllName)) <> $gc_sDllName Then Return False

	Local $sHex = _ReadFileHex($sPath)
	If @error Then Return False
	Local $aHook = _FindDllHook($sHex)
	If @error Then Return False
	Return _BytesAt($sHex, $aHook[$gc_iHookAt], 1) = "E9"
EndFunc   ;==>_FilePatched


; Копия нужна там, где файл уже изменён нами: из неё и делается откат.
; Рядом с чистым файлом копия переписывается заново, иначе патч, который всегда
; накладывается от копии, молча откатил бы обновление игры или мода
Func _EnsureBackups($sDir)
	Local $aFiles = _TargetFiles($sDir)
	For $i = 0 To UBound($aFiles) - 1
		Local $sBak = _BakPath($aFiles[$i])

		If _FilePatched($aFiles[$i]) Then
			; Без копии оригинал уже не собрать: патч наложен, а взять его неоткуда
			If Not FileExists($sBak) Then _
					Return "Потеряна резервная копия " & _ShortName($aFiles[$i]) & $gc_sBakExt
			ContinueLoop
		EndIf

		If Not FileCopy($aFiles[$i], $sBak, $FC_OVERWRITE) Then _
				Return "Не удалось создать резервную копию " & _ShortName($aFiles[$i]) & $gc_sBakExt
	Next
	Return ""
EndFunc   ;==>_EnsureBackups


; После полного отката копии не нужны: файлы и так оригинальные
Func _DeleteBackups($sDir)
	Local $aFiles = _TargetFiles($sDir)
	For $i = 0 To UBound($aFiles) - 1
		FileDelete(_BakPath($aFiles[$i]))
	Next
EndFunc   ;==>_DeleteBackups


; Перебирает все файлы, даже если один не поддался: меньше шансов остаться
; с полупропатченной игрой. Вернёт первую ошибку.
; $bOnlyPatched не трогает чистые файлы: копия рядом может быть от прошлой версии
Func _RestoreFromBackups($sDir, $bOnlyPatched = False)
	Local $aFiles = _TargetFiles($sDir)
	Local $sError = ""
	For $i = 0 To UBound($aFiles) - 1
		If Not FileExists(_BakPath($aFiles[$i])) Then ContinueLoop
		If $bOnlyPatched And Not _FilePatched($aFiles[$i]) Then ContinueLoop
		If FileCopy(_BakPath($aFiles[$i]), $aFiles[$i], $FC_OVERWRITE) Then ContinueLoop
		If $sError = "" Then $sError = "Не удалось восстановить файл " & _ShortName($aFiles[$i])
	Next
	Return $sError
EndFunc   ;==>_RestoreFromBackups


; ==========================================================
; Проверка патчей
; ==========================================================

; Состояние патча в exe определяют полтора десятка байт, их и читаем;
; dll приходится читать целиком - место врезки в ней ищется по коду

; Врезку в dll ищет вызывающий: поиск по мегабайтам стоит дороже всех проверок
; вместе взятых, а нужен он и патчу окна, и патчу настроек
Func _PopupPatchedAt($sHex, $aHook)
	Local $iAt = $aHook[$gc_iHookAt]
	If _BytesAt($sHex, $iAt, 1) <> "E9" Then Return False   ; врезки нет

	Local $iTarget = $aHook[$gc_iHookRva] + 5 + _GetSDword($sHex, $iAt + 1)
	If $iTarget = $aHook[$gc_iHookContinue] Then Return True   ; переход сразу мимо окна

	; Врезка ведёт в нашу секцию - смотрим, какая заглушка туда положена:
	; окно пропускается, только если она уходит на ту же штатную ветку
	Local $iRaw = _SectionRawByRva($sHex, $iTarget)
	If $iRaw = 0 Or Not _StubAt($sHex, $iRaw) Then Return False
	Local $iHead = _StubHeadLen()
	If _BytesAt($sHex, $iRaw + $iHead, 1) <> "E9" Then Return False
	Return $iTarget + $iHead + 5 + _GetSDword($sHex, $iRaw + $iHead + 1) = $aHook[$gc_iHookContinue]
EndFunc   ;==>_PopupPatchedAt


; Наша ли заглушка лежит по смещению. Между головой и хвостом адрес процедуры
; сохранения, он свой у каждой сборки, поэтому сверяем только код вокруг него
Func _StubAt($sHex, $iRaw)
	Local $iLead = Int(StringLen($gc_sDllStubHead) / 2)
	Return _BytesAt($sHex, $iRaw, $iLead) = $gc_sDllStubHead And _
			_BytesAt($sHex, $iRaw + $iLead + 4, Int(StringLen($gc_sDllStubTail) / 2)) = $gc_sDllStubTail
EndFunc   ;==>_StubAt


; Голова, адрес процедуры и хвост: дальше заглушки расходятся
Func _StubHeadLen()
	Return Int((StringLen($gc_sDllStubHead) + StringLen($gc_sDllStubTail)) / 2) + 4
EndFunc   ;==>_StubHeadLen


; Первая беда с патчем в exe: $bMarks выбирает подсветку, иначе патч настроек.
; Пустая строка - обе exe несут патч и он цел, про dll спрашивают отдельно
Func _ExeProblem($sDir, $bMarks)
	For $i = 0 To UBound($gc_aExeNames) - 1
		Local $sPath = $sDir & "\" & $gc_aExeNames[$i]
		Local $sWhy = $bMarks ? _MarksStateOf("", $sPath) : _ExeStateOf("", $sPath)
		If $sWhy <> "" Then Return $sWhy
	Next
	Return ""
EndFunc   ;==>_ExeProblem


; Что не так с патчем настроек в exe; пустая строка - всё на месте.
; Секции мало: она могла лечь, а врезка не встать, поэтому адреса врезок берутся
; из переходов внутри секции и обе стороны сверяются друг с другом.
; Работает и по готовому образу в памяти, и прямо по файлу: при проверке перед
; записью образ уже собран, а при опросе состояния тянуть мегабайты незачем
Func _ExeStateOf($sHex, $sPath)
	Local $sName = _ShortName($sPath)
	Local $sHead = ($sHex <> "") ? $sHex : _ReadBytes($sPath, 0, $gc_iPeHeaderSize)
	If @error Then Return "не удалось прочитать " & $sName

	; Таблица секций нужна и секции патча, и каждой врезке: разбираем один раз
	Local $aSec = _SectionTable($sHead)
	Local $iRow = _SectionRow($aSec, ".hpatch")
	If $iRow < 0 Then Return "в " & $sName & " нет секции с кодом патча"
	Local $iSecRva = $aSec[$iRow][$gc_iSecRva]
	Local $iRaw = $aSec[$iRow][$gc_iSecRaw]

	; В начале секции лежит имя файла с настройками, по нему и узнаём свой код
	Local $iMark = 16
	If _Peek($sHex, $sPath, $iRaw, $iMark) <> StringLeft($gc_sExeCode, $iMark * 2) Then _
			Return "в секции " & $sName & " чужой код"

	For $i = 0 To UBound($gc_aExeRelRefs) - 1
		Local $iOff = $gc_aExeRelRefs[$i][0]
		Local $sHook = $gc_aExeRelRefs[$i][1]
		Local $iBack = $iSecRva + $iOff + 4 + _SDwordOf(_Peek($sHex, $sPath, $iRaw + $iOff, 4))
		Local $iHookRva = $iBack - $gc_aExeRelRefs[$i][2]

		Local $iHookRaw = _RawByRvaIn($aSec, $iHookRva)
		If $iHookRaw = 0 Then Return "врезка " & $sHook & " в " & $sName & " указывает в пустоту"
		Local $sAt = _Peek($sHex, $sPath, $iHookRaw, 5)
		If StringLeft($sAt, 2) <> "E9" Then Return "врезка " & $sHook & " не встала в " & $sName
		If $iHookRva + 5 + _SDwordOf(StringTrimLeft($sAt, 2)) <> $iSecRva + _HookBlock($sHook) Then _
				Return "врезка " & $sHook & " в " & $sName & " ведёт не в секцию патча"
	Next
	Return ""
EndFunc   ;==>_ExeStateOf


; Кусок либо из готового образа, либо прямо из файла
Func _Peek($sHex, $sPath, $iAt, $iCount)
	If $sHex <> "" Then Return _BytesAt($sHex, $iAt, $iCount)
	Return _ReadBytes($sPath, $iAt, $iCount)
EndFunc   ;==>_Peek


Func _HookBlock($sName)
	For $i = 0 To UBound($gc_aExeHooks) - 1
		If $gc_aExeHooks[$i][0] = $sName Then Return $gc_aExeHooks[$i][4]
	Next
	Return 0
EndFunc   ;==>_HookBlock


; Что не так с заглушкой в dll; пустая строка - всё на месте.
; Заглушку ставит только патч настроек: одному патчу окна хватает перехода
Func _DllStubState($sPath)
	Local $sHex = _ReadFileHex($sPath)
	If @error Then Return "не удалось прочитать " & _ShortName($sPath)
	Return _DllStubStateOf($sHex)
EndFunc   ;==>_DllStubState


Func _DllStubStateOf($sHex)
	Local $aHook = _FindDllHook($sHex)
	If @error Then Return "в " & $gc_sDllName & " не найдено место врезки"
	Return _DllStubStateAt($sHex, $aHook)
EndFunc   ;==>_DllStubStateOf


; То же, но по уже найденной врезке
Func _DllStubStateAt($sHex, $aHook)
	Local $iAt = $aHook[$gc_iHookAt]
	If _BytesAt($sHex, $iAt, 1) <> "E9" Then Return "врезка не встала в " & $gc_sDllName

	Local $iTarget = $aHook[$gc_iHookRva] + 5 + _GetSDword($sHex, $iAt + 1)
	Local $iSecRva = _SectionRvaByName($sHex, ".hpatch")
	If $iSecRva = 0 Or $iTarget <> $iSecRva Then _
			Return "врезка в " & $gc_sDllName & " ведёт мимо заглушки"
	If Not _StubAt($sHex, _SectionRawByRva($sHex, $iSecRva)) Then _
			Return "в секции " & $gc_sDllName & " чужая заглушка"
	Return ""
EndFunc   ;==>_DllStubStateAt


; ==========================================================
; Наложение патчей
; ==========================================================

; Ниже все функции возвращают описание ошибки или пустую строку

; Обе правки exe за одно чтение и одну запись: файл весит мегабайты,
; а подсветку с настройками обычно ставят вместе
Func _PatchExeFile($sPath, $bTowns, $bMarks)
	If Not $bTowns And Not $bMarks Then Return ""
	Local $sHex = _ReadFileHex($sPath)
	If @error Then Return "Не удалось прочитать " & _ShortName($sPath)

	Local $sError = ""
	If $bTowns Then $sError = _PatchExe($sHex, $sPath)
	; Подсветка встаёт своей секцией за секцией настроек, врезки у них разные
	If $sError = "" And $bMarks Then $sError = _PatchMarks($sHex, $sPath)
	If $sError <> "" Then Return $sError
	Return _WriteFileHex($sPath, $sHex)
EndFunc   ;==>_PatchExeFile


; $sPath нужен только для сообщений: правка идёт по образу в $sHex
Func _PatchExe(ByRef $sHex, $sPath)
	Local $iBase = _ImageBase($sHex)

	; Всё, что зависит от сборки игры, ищем до того, как трогать файл
	Local $aHookRaw[UBound($gc_aExeHooks)], $aHookVa[UBound($gc_aExeHooks)]
	For $i = 0 To UBound($gc_aExeHooks) - 1
		Local $iAt = _FindSignature($sHex, $gc_aExeHooks[$i][1])
		If $iAt < 0 Then Return "В " & _ShortName($sPath) & " не найдена врезка " & $gc_aExeHooks[$i][0]
		$aHookRaw[$i] = $iAt + $gc_aExeHooks[$i][2]
		$aHookVa[$i] = $iBase + _SectionRvaByRaw($sHex, $aHookRaw[$i])
	Next

	Local $iScen = _FindSignature($sHex, $gc_sScenarioSig)
	If $iScen < 0 Then Return "В " & _ShortName($sPath) & " не найден указатель на сценарий"
	Local $iScenarioPtr = _GetDword($sHex, $iScen + $gc_iScenarioAt)

	Local $iSectionRva = 0
	Local $iRaw = _AddSection($sHex, ".hpatch", 0x800, $iSectionRva)   ; код секции с запасом
	If $iRaw = 0 Then Return "Не удалось добавить секцию в " & _ShortName($sPath)

	Local $sCode = _FixupExeCode($sHex, $iBase, $iSectionRva, $iScenarioPtr, $aHookVa)
	If @error Then Return "В " & _ShortName($sPath) & " нет импорта " & $sCode
	$sHex = _PutBytes($sHex, $iRaw, $sCode)

	For $i = 0 To UBound($gc_aExeHooks) - 1
		Local $iTarget = $iBase + $iSectionRva + $gc_aExeHooks[$i][4]
		$sHex = _PutBytes($sHex, $aHookRaw[$i], "E9" & _
				_IntToHexLE($iTarget - ($aHookVa[$i] + 5)) & _
				_RepeatHex("90", $gc_aExeHooks[$i][3] - 5))
	Next

	; Кривой образ на диск не уходит: сверяемся до записи
	Local $sState = _ExeStateOf($sHex, $sPath)
	If $sState <> "" Then Return "Патч собран неверно, " & $sState
	Return ""
EndFunc   ;==>_PatchExe


; Переносит код секции на её фактический адрес: ссылки внутрь себя сдвигаются,
; адреса игры берутся из этой сборки, переходы назад - от найденных врезок.
; При ошибке ставит @error и возвращает имя ненайденной функции
Func _FixupExeCode($sHex, $iBase, $iSectionRva, $iScenarioPtr, ByRef $aHookVa)
	Local $sCode = $gc_sExeCode
	Local $iShift = $iSectionRva - $gc_iExeSectionRva

	For $i = 0 To UBound($gc_aExeSecRefs) - 1
		Local $iOff = $gc_aExeSecRefs[$i]
		$sCode = _PutBytes($sCode, $iOff, _IntToHexLE(_GetDword($sCode, $iOff) + $iShift))
	Next

	For $i = 0 To UBound($gc_aExeGameRefs) - 1
		Local $sName = $gc_aExeGameRefs[$i][1]
		Local $iAddr = $iScenarioPtr
		If $sName <> "ScenarioPtr" Then
			$iAddr = _ImportSlotVa($sHex, $sName)
			If $iAddr = 0 Then Return SetError(1, 0, $sName)
		EndIf
		$sCode = _PutBytes($sCode, $gc_aExeGameRefs[$i][0], _IntToHexLE($iAddr))
	Next

	For $i = 0 To UBound($gc_aExeRelRefs) - 1
		Local $iSpot = $gc_aExeRelRefs[$i][0]
		Local $iTarget = _HookVa($gc_aExeRelRefs[$i][1], $aHookVa) + $gc_aExeRelRefs[$i][2]
		$sCode = _PutBytes($sCode, $iSpot, _
				_IntToHexLE($iTarget - ($iBase + $iSectionRva + $iSpot + 4)))
	Next
	Return $sCode
EndFunc   ;==>_FixupExeCode


Func _HookVa($sName, ByRef $aHookVa)
	For $i = 0 To UBound($gc_aExeHooks) - 1
		If $gc_aExeHooks[$i][0] = $sName Then Return $aHookVa[$i]
	Next
	Return 0
EndFunc   ;==>_HookVa


; Адрес процедуры сохранения внутри секции exe: её зовёт заглушка в dll
Func _ExeSaveProc($sPath)
	Local $sHead = _ReadBytes($sPath, 0, $gc_iPeHeaderSize)
	If @error Then Return 0
	Local $iRva = _SectionRvaByName($sHead, ".hpatch")
	If $iRva = 0 Then Return 0
	Return _ImageBase($sHead) + $iRva + $gc_iExeSaveProc
EndFunc   ;==>_ExeSaveProc


; Заглушку ставит только патч настроек: она зовёт процедуру сохранения из секции exe.
; Одному патчу окна хватает перехода сразу на штатную ветку. $iSaveProc = 0 - без заглушки
Func _PatchDll($sPath, $bSkipPopup, $iSaveProc)
	Local $sHex = _ReadFileHex($sPath)
	If @error Then Return "Не удалось прочитать " & _ShortName($sPath)

	Local $aHook = _FindDllHook($sHex)
	If @error Then Return "В " & $gc_sDllName & " не найдено место врезки"
	Local $iAt = $aHook[$gc_iHookAt], $iHookRva = $aHook[$gc_iHookRva]
	If _BytesAt($sHex, $iAt, 1) <> "E8" Then Return $gc_sDllName & " уже изменён, нужен оригинал"

	; Ровно пять байт: вытесненный вызов столько и занимал, следующая инструкция цела
	If $iSaveProc = 0 Then
		$sHex = _PutBytes($sHex, $iAt, "E9" & _IntToHexLE($aHook[$gc_iHookContinue] - ($iHookRva + 5)))
		If Not _PopupPatchedAt($sHex, $aHook) Then _
				Return "Патч собран неверно, переход в " & $gc_sDllName & " ведёт не туда"
		Return _WriteFileHex($sPath, $sHex)
	EndIf

	Local $iSectionRva = 0
	Local $iRaw = _AddSection($sHex, ".hpatch", 0x100, $iSectionRva)   ; заглушка с запасом
	If $iRaw = 0 Then Return "Не удалось добавить секцию в " & $gc_sDllName

	; Голова заглушки одна и та же, дальше расходится: с пропуском окна уходим
	; на штатную ветку, без него делаем вытесненный вызов и возвращаемся за врезку
	Local $sStub = $gc_sDllStubHead & _IntToHexLE($iSaveProc) & $gc_sDllStubTail
	Local $iAfter = $iSectionRva + _StubHeadLen()
	If $bSkipPopup Then
		$sStub &= "E9" & _IntToHexLE($aHook[$gc_iHookContinue] - ($iAfter + 5))
	Else
		$sStub &= "E8" & _IntToHexLE($aHook[$gc_iHookCall] - ($iAfter + 5))
		$sStub &= "E9" & _IntToHexLE(($iHookRva + 5) - ($iAfter + 10))
	EndIf

	$sHex = _PutBytes($sHex, $iRaw, $sStub)
	$sHex = _PutBytes($sHex, $iAt, "E9" & _IntToHexLE($iSectionRva - ($iHookRva + 5)))

	Local $sState = _DllStubStateAt($sHex, $aHook)
	If $sState = "" And _PopupPatchedAt($sHex, $aHook) <> $bSkipPopup Then $sState = "пропуск окна собран не так, как просили"
	If $sState <> "" Then Return "Патч собран неверно, " & $sState
	Return _WriteFileHex($sPath, $sHex)
EndFunc   ;==>_PatchDll


; ==========================================================
; Подсветка несобранных
; ==========================================================

; Код подсветки встаёт на оба выхода прохода тумана по клеткам карты: для
; видимой клетки входа несобранного объекта рисует искры и выходит штатным
; эпилогом, который сам и вытеснил. Своя секция .hmark, с патчем настроек
; не пересекается

Func _PatchMarks(ByRef $sHex, $sPath)
	Local $iBase = _ImageBase($sHex)

	; Всё, что зависит от сборки игры, ищем до того, как трогать файл
	Local $oAddr = _MarkAddresses($sHex)
	If @error Then Return "В " & _ShortName($sPath) & " не найден адрес " & $oAddr
	Local $aSec = _SectionTable($sHex)
	Local $iHookLen = Int(StringLen($gc_sMarkHookOrig) / 2)
	Local $aHookRaw[UBound($gc_aMarkHooks)]
	For $i = 0 To UBound($gc_aMarkHooks) - 1
		$aHookRaw[$i] = _RawByRvaIn($aSec, $oAddr[$gc_aMarkHooks[$i]] - $iBase)
		; Эпилог код секции выполняет сам, поэтому он обязан быть ровно таким
		If _BytesAt($sHex, $aHookRaw[$i], $iHookLen) <> $gc_sMarkHookOrig Then _
				Return "В " & _ShortName($sPath) & " на месте врезки подсветки чужой код"
	Next

	Local $iSectionRva = 0
	Local $iRaw = _AddSection($sHex, ".hmark", $gc_iMarkSectionSize, $iSectionRva)
	If $iRaw = 0 Then Return "Не удалось добавить секцию в " & _ShortName($sPath)
	$sHex = _PutBytes($sHex, $iRaw, _MarkCode($iSectionRva, $oAddr))

	For $i = 0 To UBound($gc_aMarkHooks) - 1
		Local $iHookVa = $oAddr[$gc_aMarkHooks[$i]]
		; Адрес врезки остаётся в секции: по нему читается состояние патча
		$sHex = _PutBytes($sHex, $iRaw + $gc_iMarkHookSlots + $i * 4, _IntToHexLE($iHookVa - $iBase))
		$sHex = _PutBytes($sHex, $aHookRaw[$i], "E9" & _
				_IntToHexLE($iBase + $iSectionRva + $gc_iMarkEntry - ($iHookVa + 5)) & _
				_RepeatHex("90", $iHookLen - 5))
	Next

	; Кривой образ на диск не уходит: сверяемся до записи
	Local $sState = _MarksStateOf($sHex, $sPath)
	If $sState <> "" Then Return "Подсветка собрана неверно, " & $sState
	Return ""
EndFunc   ;==>_PatchMarks


; Адреса игры для кода подсветки, по именам. Ищутся по коду вокруг них и по
; импорту: новая сборка игры двигает код, но не переписывает его.
; При ошибке ставит @error и возвращает имя ненайденного адреса
Func _MarkAddresses($sHex)
	Local $oAddr[]
	Local $iBase = _ImageBase($sHex)

	; Одна сигнатура даёт несколько адресов, поэтому ищем каждую по разу
	Local $aAt[UBound($gc_aMarkSigs)]
	For $i = 0 To UBound($gc_aMarkSigs) - 1
		$aAt[$i] = _FindSignature($sHex, $gc_aMarkSigs[$i])
	Next

	For $i = 0 To UBound($gc_aMarkAddrs) - 1
		Local $sName = $gc_aMarkAddrs[$i][0]
		Local $iSig = $aAt[$gc_aMarkAddrs[$i][1]]
		If $iSig < 0 Then Return SetError(1, 0, $sName)
		Local $iRaw = $iSig + $gc_aMarkAddrs[$i][2]
		Local $iVa = $iBase + _SectionRvaByRaw($sHex, $iRaw)
		Switch $gc_aMarkAddrs[$i][3]
			Case "abs"   ; в инструкции лежит сам адрес
				$oAddr[$sName] = _GetDword($sHex, $iRaw)
			Case "rel"   ; rel32 вызова считается от конца поля
				$oAddr[$sName] = $iVa + 4 + _GetSDword($sHex, $iRaw)
			Case Else    ; нужен адрес самого места
				$oAddr[$sName] = $iVa
		EndSwitch
	Next

	For $i = 0 To UBound($gc_aMarkImports) - 1
		Local $iSlot = _ImportSlotVa($sHex, $gc_aMarkImports[$i][2], $gc_aMarkImports[$i][1])
		If $iSlot = 0 Then Return SetError(1, 0, $gc_aMarkImports[$i][2])
		$oAddr[$gc_aMarkImports[$i][0]] = $iSlot
	Next
	Return $oAddr
EndFunc   ;==>_MarkAddresses


; Секция подсветки на её фактическом адресе: куски кода и данных ложатся в нули,
; ссылки внутрь себя сдвигаются, адреса игры подставляются найденные
Func _MarkCode($iSectionRva, ByRef $oAddr)
	Local $sCode = _RepeatHex("00", $gc_iMarkSectionSize)
	Local $aChunks = _MarkChunks()
	For $i = 0 To UBound($aChunks) - 1
		$sCode = _PutBytes($sCode, $aChunks[$i][0], $aChunks[$i][1])
	Next

	Local $iShift = $iSectionRva - $gc_iMarkSectionRva
	For $i = 0 To UBound($gc_aMarkSecRefs) - 1
		Local $iOff = $gc_aMarkSecRefs[$i]
		$sCode = _PutBytes($sCode, $iOff, _IntToHexLE(_GetDword($sCode, $iOff) + $iShift))
	Next

	For $i = 0 To UBound($gc_aMarkGameRefs) - 1
		$sCode = _PutBytes($sCode, $gc_aMarkGameRefs[$i][0], _IntToHexLE($oAddr[$gc_aMarkGameRefs[$i][1]]))
	Next
	Return $sCode
EndFunc   ;==>_MarkCode


; Что не так с подсветкой в exe; пустая строка - всё на месте. Адреса врезок
; лежат в начале секции, по ним сверяем, что переходы ведут в неё.
; Как и _ExeStateOf, работает и по образу в памяти, и прямо по файлу
Func _MarksStateOf($sHex, $sPath)
	Local $sName = _ShortName($sPath)
	Local $sHead = ($sHex <> "") ? $sHex : _ReadBytes($sPath, 0, $gc_iPeHeaderSize)
	If @error Then Return "не удалось прочитать " & $sName

	Local $aSec = _SectionTable($sHead)
	Local $iRow = _SectionRow($aSec, ".hmark")
	If $iRow < 0 Then Return "в " & $sName & " нет секции подсветки"
	Local $iSecRva = $aSec[$iRow][$gc_iSecRva]
	Local $iRaw = $aSec[$iRow][$gc_iSecRaw]
	If _Peek($sHex, $sPath, $iRaw, Int(StringLen($gc_sMarkId) / 2)) <> $gc_sMarkId Then _
			Return "в секции подсветки " & $sName & " чужой код"

	For $i = 0 To UBound($gc_aMarkHooks) - 1
		Local $iHookRva = _DwordOf(_Peek($sHex, $sPath, $iRaw + $gc_iMarkHookSlots + $i * 4, 4))
		Local $iHookRaw = _RawByRvaIn($aSec, $iHookRva)
		If $iHookRaw = 0 Then Return "врезка подсветки в " & $sName & " указывает в пустоту"
		Local $sAt = _Peek($sHex, $sPath, $iHookRaw, 5)
		If StringLeft($sAt, 2) <> "E9" Then Return "врезка подсветки не встала в " & $sName
		If $iHookRva + 5 + _SDwordOf(StringTrimLeft($sAt, 2)) <> $iSecRva + $gc_iMarkEntry Then _
				Return "врезка подсветки в " & $sName & " ведёт не в секцию"
	Next
	Return ""
EndFunc   ;==>_MarksStateOf


; ==========================================================
; Место врезки в HD_HOTA.dll
; ==========================================================

; Врезка ищется по коду вокруг вытесняемого вызова, а не по смещению в файле:
; обновление HD-мода, двигающее код, патчу не мешает.
;   84 C0                 test al, al
;   0F 85 xx xx xx xx     jne <штатная ветка «стартовать без окна»>
;   E8 xx xx xx xx        call <подготовка окна>, сюда и врезаемся
;   8D 85 E8 FD FF FF     lea eax, [ebp - 0x218]
; Шаг допускает и E9: пропатченный файл находится тем же поиском.
; Отдаёт [смещение врезки, её RVA, RVA штатной ветки, RVA вытесняемого вызова],
; поля по индексам $gc_iHook*. @error - врезки нет или она не одна
Func _FindDllHook($sHex)
	; Шаг задан парой байт, в шаблон он идёт перечислением: E8 либо E9
	Local $sStep = StringRegExpReplace($gc_sDllSigStep, "(..)(?!$)", "$1|")
	Local $iFound = _FindSignature($sHex, $gc_sDllSigHead & "????????(?:" & $sStep & ")????????" & $gc_sDllSigTail)
	If $iFound < 0 Then Return SetError(1, 0, 0)

	; rel32 перехода jne лежит сразу за сигнатурой-головой, врезка за ним
	Local $iJneRel = Int(StringLen($gc_sDllSigHead) / 2)
	Local $aHook[4]
	$aHook[$gc_iHookAt] = $iFound + $iJneRel + 4
	$aHook[$gc_iHookRva] = _SectionRvaByRaw($sHex, $aHook[$gc_iHookAt])
	If $aHook[$gc_iHookRva] = 0 Then Return SetError(1, 0, 0)
	$aHook[$gc_iHookContinue] = $aHook[$gc_iHookRva] + _GetSDword($sHex, $iFound + $iJneRel)
	$aHook[$gc_iHookCall] = $aHook[$gc_iHookRva] + 5 + _GetSDword($sHex, $aHook[$gc_iHookAt] + 1)
	Return $aHook
EndFunc   ;==>_FindDllHook


; ==========================================================
; Работа с PE
; ==========================================================

; Добавляет секцию и возвращает её смещение в файле; 0 - не получилось.
; Её адрес в образе уходит в $iNewRva
Func _AddSection(ByRef $sHex, $sName, $iSize, ByRef $iNewRva)
	Local $iPe = _GetDword($sHex, $PE_LFANEW_AT)
	If _GetDword($sHex, $iPe) <> $PE_SIGNATURE Then Return 0

	Local $iCount = _GetWord($sHex, $iPe + $PE_SEC_COUNT)
	Local $iOpt = $iPe + $PE_OPT_AT
	Local $iTable = $iOpt + _GetWord($sHex, $iPe + $PE_OPT_SIZE)
	Local $iSecAlign = _GetDword($sHex, $iOpt + $OPT_SEC_ALIGN)
	Local $iFileAlign = _GetDword($sHex, $iOpt + $OPT_FILE_ALIGN)

	; Новая секция встаёт за последней: её адрес плюс размер в памяти
	Local $iLast = $iTable + ($iCount - 1) * $ROW_SIZE
	$iNewRva = _AlignUp(_GetDword($sHex, $iLast + $ROW_RVA) + _GetDword($sHex, $iLast + $ROW_VSIZE), $iSecAlign)

	; Хватает ли в заголовке места под ещё одну запись
	Local $iFirstRaw = 0x7FFFFFFF
	For $i = 0 To $iCount - 1
		Local $iRaw = _GetDword($sHex, $iTable + $i * $ROW_SIZE + $ROW_RAW)
		If $iRaw < $iFirstRaw Then $iFirstRaw = $iRaw
	Next
	Local $iFree = $iTable + $iCount * $ROW_SIZE
	If $iFree + $ROW_SIZE > $iFirstRaw Then Return 0

	Local $iFileSize = StringLen($sHex) / 2
	Local $iNewRaw = _AlignUp($iFileSize, $iFileAlign)
	Local $iNewRawSize = _AlignUp($iSize, $iFileAlign)

	; Хвост записи - перемещения, номера строк и их счётчики, все нулевые
	Local $sHeader = _SectionNameHex($sName)
	$sHeader &= _IntToHexLE($iSize) & _IntToHexLE($iNewRva) & _IntToHexLE($iNewRawSize) & _IntToHexLE($iNewRaw)
	$sHeader &= _RepeatHex("00", 12) & _IntToHexLE($SEC_FLAGS_CODE_RWX)

	$sHex = _PutBytes($sHex, $iFree, $sHeader)
	$sHex = _PutBytes($sHex, $iPe + $PE_SEC_COUNT, StringLeft(_IntToHexLE($iCount + 1), 4))
	$sHex = _PutBytes($sHex, $iOpt + $OPT_IMAGE_SIZE, _IntToHexLE(_AlignUp($iNewRva + $iSize, $iSecAlign)))

	$sHex &= _RepeatHex("00", $iNewRaw - $iFileSize + $iNewRawSize)
	Return $iNewRaw
EndFunc   ;==>_AddSection


; Таблица секций: строка на секцию, поля по индексам $gc_iSec*.
; Разбор заголовка один на всех, дальше по таблице ищут и по имени, и по адресу
Func _SectionTable($sHex)
	Local $aNone[0][5]
	Local $iPe = _GetDword($sHex, $PE_LFANEW_AT)
	If _GetDword($sHex, $iPe) <> $PE_SIGNATURE Then Return $aNone

	Local $iCount = _GetWord($sHex, $iPe + $PE_SEC_COUNT)
	Local $iTable = $iPe + $PE_OPT_AT + _GetWord($sHex, $iPe + $PE_OPT_SIZE)
	Local $aSec[$iCount][5]
	For $i = 0 To $iCount - 1
		Local $iRow = $iTable + $i * $ROW_SIZE
		$aSec[$i][$gc_iSecName] = _BytesAt($sHex, $iRow, 8)
		$aSec[$i][$gc_iSecVSize] = _GetDword($sHex, $iRow + $ROW_VSIZE)
		$aSec[$i][$gc_iSecRva] = _GetDword($sHex, $iRow + $ROW_RVA)
		$aSec[$i][$gc_iSecRawSize] = _GetDword($sHex, $iRow + $ROW_RAW_SIZE)
		$aSec[$i][$gc_iSecRaw] = _GetDword($sHex, $iRow + $ROW_RAW)
	Next
	Return $aSec
EndFunc   ;==>_SectionTable


; Строка секции по имени; -1 - такой секции нет
Func _SectionRow(ByRef $aSec, $sName)
	Local $sWant = _SectionNameHex($sName)
	For $i = 0 To UBound($aSec) - 1
		If $aSec[$i][$gc_iSecName] = $sWant Then Return $i
	Next
	Return -1
EndFunc   ;==>_SectionRow


; Смещение в файле по адресу в образе; 0 - адрес вне секций.
; Размер берётся больший из двух: в памяти секция бывает длиннее, чем на диске
Func _RawByRvaIn(ByRef $aSec, $iRva)
	For $i = 0 To UBound($aSec) - 1
		Local $iSize = $aSec[$i][$gc_iSecVSize]
		If $aSec[$i][$gc_iSecRawSize] > $iSize Then $iSize = $aSec[$i][$gc_iSecRawSize]
		If $iRva >= $aSec[$i][$gc_iSecRva] And $iRva < $aSec[$i][$gc_iSecRva] + $iSize Then _
				Return $aSec[$i][$gc_iSecRaw] + ($iRva - $aSec[$i][$gc_iSecRva])
	Next
	Return 0
EndFunc   ;==>_RawByRvaIn


; Смещение секции в файле по её начальному адресу; 0 - такой секции нет
Func _SectionRawByRva($sHex, $iRva)
	Local $aSec = _SectionTable($sHex)
	For $i = 0 To UBound($aSec) - 1
		If $aSec[$i][$gc_iSecRva] = $iRva Then Return $aSec[$i][$gc_iSecRaw]
	Next
	Return 0
EndFunc   ;==>_SectionRawByRva


; ==========================================================
; Поиск по сигнатуре
; ==========================================================

; Ищет байты, где ?? - любой байт; -1, если совпадений не ровно одно.
; Сигнатура идёт в регулярку как есть, поэтому в ней годится и перечисление (?:E8|E9).
; Проход StringInStr по exe игры стоит около 100 мс, регулярка - около 10
Func _FindSignature($sHex, $sSig)
	Local $sPattern = StringReplace($sSig, "??", "[0-9A-Fa-f]{2}")

	Local $iFound = -1, $iPos = 1
	While 1
		Local $aMatch = StringRegExp($sHex, $sPattern, $STR_REGEXPARRAYMATCH, $iPos)
		If @error Then ExitLoop
		Local $iStart = @extended - StringLen($aMatch[0])   ; @extended указывает сразу за совпадением
		$iPos = $iStart + 1

		; Совпадение считается только на границе байта: в шестнадцатеричной
		; строке те же символы попадаются и со сдвигом на полбайта
		If Mod($iStart, 2) = 0 Then ContinueLoop
		If $iFound >= 0 Then Return -1
		$iFound = Int(($iStart - 1) / 2)
	WEnd
	Return $iFound
EndFunc   ;==>_FindSignature


; Имя секции в заголовке - восемь байт, добитых нулями
Func _SectionNameHex($sName)
	Local $sHex = ""
	For $i = 1 To 8
		If $i <= StringLen($sName) Then
			$sHex &= Hex(Asc(StringMid($sName, $i, 1)), 2)
		Else
			$sHex &= "00"
		EndIf
	Next
	Return $sHex
EndFunc   ;==>_SectionNameHex


; Смещение секции в файле по её имени; 0 - такой секции нет.
; Хватает заголовка PE, весь файл читать незачем
Func _SectionRawByName($sHex, $sName)
	Local $aSec = _SectionTable($sHex)
	Local $iRow = _SectionRow($aSec, $sName)
	Return ($iRow < 0) ? 0 : $aSec[$iRow][$gc_iSecRaw]
EndFunc   ;==>_SectionRawByName


Func _SectionRvaByName($sHex, $sName)
	Local $aSec = _SectionTable($sHex)
	Local $iRow = _SectionRow($aSec, $sName)
	Return ($iRow < 0) ? 0 : $aSec[$iRow][$gc_iSecRva]
EndFunc   ;==>_SectionRvaByName


; Адрес в образе по смещению в файле; 0 - смещение вне секций
Func _SectionRvaByRaw($sHex, $iRaw)
	Local $aSec = _SectionTable($sHex)
	For $i = 0 To UBound($aSec) - 1
		Local $iStart = $aSec[$i][$gc_iSecRaw]
		If $iRaw >= $iStart And $iRaw < $iStart + $aSec[$i][$gc_iSecRawSize] Then _
				Return $aSec[$i][$gc_iSecRva] + ($iRaw - $iStart)
	Next
	Return 0
EndFunc   ;==>_SectionRvaByRaw


Func _ImageBase($sHex)
	Return _GetDword($sHex, _GetDword($sHex, $PE_LFANEW_AT) + $PE_OPT_AT + $OPT_IMAGE_BASE)
EndFunc   ;==>_ImageBase


Func _ReadAsciiz($sHex, $iAt)
	Local $sText = ""
	For $i = 0 To 63
		Local $sByte = _BytesAt($sHex, $iAt + $i, 1)
		If $sByte = "" Or $sByte = "00" Then ExitLoop
		$sText &= Chr(Dec($sByte))
	Next
	Return $sText
EndFunc   ;==>_ReadAsciiz


; Адрес ячейки импорта по имени функции; 0 - не нашлась.
; В каждой сборке они лежат по-своему, поэтому адрес берётся из таблицы импортов
Func _ImportSlotVa($sHex, $sFunc, $sDll = "kernel32.dll")
	Local $iPe = _GetDword($sHex, $PE_LFANEW_AT)
	Local $iImport = _GetDword($sHex, $iPe + $PE_OPT_AT + $OPT_IMPORT_DIR)
	If $iImport = 0 Then Return 0
	; Запись импорта: OriginalFirstThunk, TimeDateStamp, ForwarderChain, Name, FirstThunk
	Local Const $IMP_NAME = 12, $IMP_FIRST_THUNK = 16, $IMP_ROW_SIZE = 20

	; Таблица секций нужна на каждое имя в импорте, поэтому разбирается один раз
	Local $aSec = _SectionTable($sHex)
	Local $iAt = _RawByRvaIn($aSec, $iImport)
	If $iAt = 0 Then Return 0

	While 1
		Local $iNameRva = _GetDword($sHex, $iAt + $IMP_NAME)
		Local $iFirst = _GetDword($sHex, $iAt + $IMP_FIRST_THUNK)
		If $iNameRva = 0 And $iFirst = 0 Then ExitLoop

		; Имя вне секций читать нечем: без проверки _ReadAsciiz пошёл бы от начала файла
		Local $iNameRaw = _RawByRvaIn($aSec, $iNameRva)
		If $iNameRaw > 0 And StringLower(_ReadAsciiz($sHex, $iNameRaw)) = $sDll Then
			Local $iThunks = _GetDword($sHex, $iAt)
			If $iThunks = 0 Then $iThunks = $iFirst
			Local $iRaw = _RawByRvaIn($aSec, $iThunks)
			Local $i = 0
			While $iRaw > 0
				Local $iEntry = _GetDword($sHex, $iRaw + $i * 4)
				If $iEntry = 0 Then ExitLoop
				; Старший бит - импорт по номеру, имени нет. Сравниваем с десятичным:
				; литерал 0x80000000 AutoIt считает знаковым
				If $iEntry < 2147483648 Then
					Local $iEntryRaw = _RawByRvaIn($aSec, $iEntry)
					; Запись начинается с подсказки в два байта, дальше само имя
					If $iEntryRaw > 0 And _ReadAsciiz($sHex, $iEntryRaw + 2) = $sFunc Then _
							Return _ImageBase($sHex) + $iFirst + $i * 4
				EndIf
				$i += 1
			WEnd
		EndIf
		$iAt += $IMP_ROW_SIZE
	WEnd
	Return 0
EndFunc   ;==>_ImportSlotVa


; ==========================================================
; Мелочи
; ==========================================================

; В сообщениях об ошибке хватает имени файла: папка у всех одна, она же
; выбрана в окне выше, а путь целиком только мешает читать
Func _ShortName($sPath)
	Local $aParts = StringSplit($sPath, "\")
	Return $aParts[$aParts[0]]
EndFunc   ;==>_ShortName


; Хвостовой слэш мешает склеивать путь, но у корня диска он часть пути
Func _TrimSlash($sPath)
	Return StringRegExpReplace($sPath, "(?<!:)\\+$", "")
EndFunc   ;==>_TrimSlash


Func _GameIsRunning()
	For $i = 0 To UBound($gc_aExeNames) - 1
		If ProcessExists($gc_aExeNames[$i]) Then Return True
	Next
	Return False
EndFunc   ;==>_GameIsRunning


Func _AlignUp($iValue, $iAlign)
	Return Int(($iValue + $iAlign - 1) / $iAlign) * $iAlign
EndFunc   ;==>_AlignUp


; Удвоением, а не по одному: секция подсветки - это 45 тысяч нулевых байт,
; и склейка по кусочку копировала бы растущую строку на каждом шаге
Func _RepeatHex($sText, $iTimes)
	If $iTimes <= 0 Then Return ""
	Local $s = $sText
	While StringLen($s) < StringLen($sText) * $iTimes
		$s &= $s
	WEnd
	Return StringLeft($s, StringLen($sText) * $iTimes)
EndFunc   ;==>_RepeatHex


Func _BytesAt($sHex, $iOffset, $iCount)
	Return StringMid($sHex, $iOffset * 2 + 1, $iCount * 2)
EndFunc   ;==>_BytesAt


; @error, если кусок не помещается: иначе он молча уехал бы в хвост строки
; и образ стал бы длиннее файла, из которого собран
Func _PutBytes($sHex, $iOffset, $sBytes)
	If $iOffset < 0 Or $iOffset * 2 + StringLen($sBytes) > StringLen($sHex) Then Return SetError(1, 0, $sHex)
	Return StringLeft($sHex, $iOffset * 2) & $sBytes & StringMid($sHex, $iOffset * 2 + StringLen($sBytes) + 1)
EndFunc   ;==>_PutBytes


Func _GetDword($sHex, $iOffset)
	Return _DwordOf(_BytesAt($sHex, $iOffset, 4))
EndFunc   ;==>_GetDword


Func _DwordOf($s)
	Return Dec(StringMid($s, 7, 2) & StringMid($s, 5, 2) & StringMid($s, 3, 2) & StringLeft($s, 2))
EndFunc   ;==>_DwordOf


Func _SDwordOf($s)
	Local $iValue = _DwordOf($s)
	If $iValue > 0x7FFFFFFF Then $iValue -= 0x100000000
	Return $iValue
EndFunc   ;==>_SDwordOf


Func _GetWord($sHex, $iOffset)
	Local $s = _BytesAt($sHex, $iOffset, 2)
	Return Dec(StringMid($s, 3, 2) & StringLeft($s, 2))
EndFunc   ;==>_GetWord


; Относительные переходы в коде знаковые, а _GetDword отдаёт беззнаковое
Func _GetSDword($sHex, $iOffset)
	Return _SDwordOf(_BytesAt($sHex, $iOffset, 4))
EndFunc   ;==>_GetSDword


; Int() обязателен: деление в AutoIt даёт Double, а Hex() от Double отдаёт
; куски его двоичного представления вместо самого числа
Func _IntToHexLE($iValue)
	Local $s = Hex(Int($iValue), 8)
	Return StringMid($s, 7, 2) & StringMid($s, 5, 2) & StringMid($s, 3, 2) & StringLeft($s, 2)
EndFunc   ;==>_IntToHexLE


; Кусок файла шестнадцатеричной строкой
Func _ReadBytes($sPath, $iOffset, $iCount)
	Local $hFile = FileOpen($sPath, $FO_READ + $FO_BINARY)
	If $hFile = -1 Then Return SetError(1, 0, "")
	FileSetPos($hFile, $iOffset, $FILE_BEGIN)
	Local $bData = FileRead($hFile, $iCount)
	FileClose($hFile)
	Return StringTrimLeft(String($bData), 2)
EndFunc   ;==>_ReadBytes


Func _ReadFileHex($sPath)
	Local $hFile = FileOpen($sPath, $FO_READ + $FO_BINARY)
	If $hFile = -1 Then Return SetError(1, 0, "")
	Local $bData = FileRead($hFile)
	FileClose($hFile)
	Return StringTrimLeft(String($bData), 2)
EndFunc   ;==>_ReadFileHex


Func _WriteFileHex($sPath, $sHex)
	Local $hFile = FileOpen($sPath, $FO_OVERWRITE + $FO_BINARY)
	If $hFile = -1 Then Return "Не удалось записать " & _ShortName($sPath)
	Local $bOk = FileWrite($hFile, Binary("0x" & $sHex))
	FileClose($hFile)
	Return $bOk ? "" : "Не удалось записать " & _ShortName($sPath)
EndFunc   ;==>_WriteFileHex

