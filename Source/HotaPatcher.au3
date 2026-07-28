#cs ----------------------------------------------------------------------------

	Патчер для Heroes 3: Horn of the Abyss (HotA 1.8.0 + HD mod 5.7 R33)

	Патч 1. Убирает окно «Турнирные правила», которое HD-мод показывает
	при каждом нажатии «Начать».

	Патч 2. Запоминает выбранные стартовые город, героя и бонус всех игроков
	и подставляет их на следующей случайной карте.

	Оба патча трогают только файлы игры и полностью откатываются
	восстановлением резервных копий, которые патчер делает сам.

#ce ----------------------------------------------------------------------------

#pragma compile(Out, ..\Release\HotAPatcher.exe)
#pragma compile(Icon, Assets\Game.ico)
#pragma compile(ProductName, HotAPatcher)
#pragma compile(FileDescription, Патчер для Heroes 3 HotA)
#pragma compile(FileVersion, 1.0.0.0)
#pragma compile(LegalCopyright, )
#pragma compile(x64, false)

#NoTrayIcon

#include <FileConstants.au3>
#include <GDIPlus.au3>
#include <GUIConstantsEx.au3>
#include <StaticConstants.au3>
#include <WinAPIGdi.au3>
#include <WinAPISysWin.au3>
#include <WindowsConstants.au3>
#include "PatchData.au3"

Global Const $g_sTitle = "HotAPatcher 1.0"

; названия патчей: ими подписаны галочки, ими же помечаются сообщения
Global Const $g_sPopupName = "Не показывать это окно при создании новой игры"
Global Const $g_sTownsName = "Запоминать настройки для новой игры между сессиями"

Global Const $g_sDllName = "HD_HOTA.dll"
Global Const $g_aExeNames[2] = ["h3hota.exe", "h3hota HD.exe"]

; для «получилось» и «ошибка» системных цветов нет, остальное берём у Windows
Global Const $g_iColorOk = 0x0F7B0F
Global Const $g_iColorBad = 0xC42B1C
Global $g_iColorText, $g_iColorMuted, $g_iColorBg, $g_iColorPanel, $g_iColorBorder

Global Const $g_iWinWidth = 450
Global Const $g_iMargin = 29        ; 8 серого поля, рамка и 20 воздуха внутри белой области
Global Const $g_iInset = 8          ; серое поле слева и справа от белой области
Global Const $g_iLineHeight = 16    ; строка состояния
Global Const $g_iGap = 20           ; одинаковый вертикальный отступ между блоками
Global Const $g_iContentWidth = $g_iWinWidth - $g_iMargin * 2
Global Const $g_iBtnWidth = 88      ; одинаковая ширина всех кнопок
Global Const $g_iBtnHeight = 26
Global Const $g_iPeHeaderSize = 0x1000   ; заголовок PE вместе с таблицей секций

Global $g_hGui
Global $g_idInput, $g_idBrowse, $g_idApply, $g_idCancel, $g_idPopup, $g_idTowns
Global $g_idPopupState, $g_idTownsState, $g_idPathState
; что реально установлено в игре сейчас
Global $g_bPopupOn = False, $g_bTownsOn = False
Global $g_sLastDir = "", $g_sAutoDir = ""
Global $g_ahBitmaps[3] = [0, 0, 0]

Main()

Func Main()
	If Not @Compiled Then FileChangeDir(@ScriptDir)

	InitColors()
	BuildGui()

	Local $sStart = DetectGameDir()
	If $sStart <> "" Then GUICtrlSetData($g_idInput, $sStart)
	RefreshState()
	GUISetState(@SW_SHOW, $g_hGui)   ; показываем уже готовое окно

	While True
		Switch GUIGetMsg()
			Case $GUI_EVENT_CLOSE
				ExitLoop

			Case $g_idBrowse
				BrowseForDir()

			Case $g_idPopup, $g_idTowns
				UpdateButtons()

			Case $g_idApply
				DoApply()

			Case $g_idCancel
				ExitLoop

			Case Else
				If GUICtrlRead($g_idInput) <> $g_sLastDir Then RefreshState()
		EndSwitch
	WEnd

	Cleanup()
EndFunc   ;==>Main

; ------------------------------------------------------------------ интерфейс

Func InitColors()
	$g_iColorText = SysColor($COLOR_WINDOWTEXT)
	$g_iColorMuted = SysColor($COLOR_GRAYTEXT)
	$g_iColorBg = SysColor($COLOR_BTNFACE)      ; фон окна, как в системных диалогах
	$g_iColorPanel = SysColor($COLOR_WINDOW)    ; рабочая область
	$g_iColorBorder = SysColor($COLOR_3DSHADOW) ; её рамка
EndFunc   ;==>InitColors

; GetSysColor отдаёт COLORREF, то есть BGR, а GUICtrlSet* ждут RGB
Func SysColor($iIndex)
	Return _WinAPI_SwitchColor(_WinAPI_GetSysColor($iIndex))
EndFunc   ;==>SysColor

Func BuildGui()
	$g_hGui = GUICreate($g_sTitle, $g_iWinWidth, 100)   ; высоту подгоняем в конце
	GUISetBkColor($g_iColorBg)
	GUISetFont(9, 400, 0, "Segoe UI")
	SetWindowIcon()
	_GDIPlus_Startup()

	Local $idIcon = GUICtrlCreatePic("", $g_iMargin, 15, 32, 32)
	$g_ahBitmaps[0] = LoadPicture($idIcon, "Icon.png")

	Local $idTitle = GUICtrlCreateLabel("Патчер для Heroes 3: Horn of the Abyss", $g_iMargin + 42, 13, 344, 24)
	GUICtrlSetFont($idTitle, 12, 600, 0, "Segoe UI")
	GUICtrlSetColor($idTitle, $g_iColorText)
	GUICtrlSetBkColor($idTitle, $g_iColorBg)

	Local $idSubtitle = GUICtrlCreateLabel("Отметьте, что применить к игре", $g_iMargin + 42, 37, 344, 18)
	GUICtrlSetColor($idSubtitle, $g_iColorMuted)
	GUICtrlSetBkColor($idSubtitle, $g_iColorBg)

	Local $iPanelTop = 64

	; дальше идём сверху вниз, отступ между блоками всегда одинаковый
	Local $y = $iPanelTop + 1 + $g_iGap

	$g_idPopup = GUICtrlCreateCheckbox(" " & $g_sPopupName, $g_iMargin, $y, $g_iContentWidth, 20)
	GUICtrlSetColor($g_idPopup, $g_iColorText)
	GUICtrlSetBkColor($g_idPopup, $g_iColorPanel)
	$y += 22

	$g_idPopupState = CreateStateLabel($y)
	$y += 22

	Local $idShot = GUICtrlCreatePic("", $g_iMargin, $y, $g_iContentWidth, 126)
	$g_ahBitmaps[1] = LoadPicture($idShot, "Popup.png")
	$y += 126 + $g_iGap

	$g_idTowns = GUICtrlCreateCheckbox(" " & $g_sTownsName, $g_iMargin, $y, $g_iContentWidth, 20)
	GUICtrlSetColor($g_idTowns, $g_iColorText)
	GUICtrlSetBkColor($g_idTowns, $g_iColorPanel)
	$y += 22

	$g_idTownsState = CreateStateLabel($y)
	$y += 22

	Local $idTownsPic = GUICtrlCreatePic("", $g_iMargin, $y, $g_iContentWidth, 126)
	$g_ahBitmaps[2] = LoadPicture($idTownsPic, "Towns.png")
	$y += 126 + $g_iGap

	Local $idPathLabel = GUICtrlCreateLabel("Папка с игрой", $g_iMargin, $y, 300, 16)
	GUICtrlSetColor($idPathLabel, $g_iColorText)
	GUICtrlSetBkColor($idPathLabel, $g_iColorPanel)
	$y += 20

	$g_idInput = GUICtrlCreateInput("", $g_iMargin, $y, $g_iContentWidth - $g_iBtnWidth - 8, 24)
	$g_idBrowse = GUICtrlCreateButton("Обзор...", $g_iMargin + $g_iContentWidth - $g_iBtnWidth, $y - 1, _
			$g_iBtnWidth, $g_iBtnHeight)
	$y += 28

	$g_idPathState = CreateStateLabel($y, 0)
	$y += $g_iLineHeight + $g_iGap

	Local $iPanelBottom = $y
	Local $iRight = $g_iWinWidth - $g_iInset - 1
	Local $iButtons = $iPanelBottom + 12
	$g_idApply = GUICtrlCreateButton("Применить", $iRight - $g_iBtnWidth, $iButtons, $g_iBtnWidth, $g_iBtnHeight)
	$g_idCancel = GUICtrlCreateButton("Отмена", $iRight - $g_iBtnWidth * 2 - 8, $iButtons, $g_iBtnWidth, $g_iBtnHeight)

	; белое поле создаётся раньше рамки: тогда рамка лежит ниже него
	; и с WS_CLIPSIBLINGS рисует только выступающий по краю контур
	Local $iFrame = $g_iInset, $iPanelHeight = $iPanelBottom - $iPanelTop
	Backdrop(GUICtrlCreateLabel("", $iFrame + 1, $iPanelTop + 1, _
			$g_iWinWidth - ($iFrame + 1) * 2, $iPanelHeight - 2), $g_iColorPanel)
	Backdrop(GUICtrlCreateLabel("", $iFrame, $iPanelTop, $g_iWinWidth - $iFrame * 2, $iPanelHeight), $g_iColorBorder)

	_GDIPlus_Shutdown()
	FitWindow($iButtons + $g_iBtnHeight + 12)
EndFunc   ;==>BuildGui

; высота окна считается по разметке: иначе её приходится править руками
; после каждого изменения содержимого
Func FitWindow($iContentHeight)
	Local $aWin = WinGetPos($g_hGui)
	Local $aClient = WinGetClientSize($g_hGui)
	Local $iHeight = $iContentHeight + $aWin[3] - $aClient[1]   ; плюс заголовок и рамка
	WinMove($g_hGui, "", (@DesktopWidth - $aWin[2]) / 2, (@DesktopHeight - $iHeight) / 2, $aWin[2], $iHeight)
EndFunc   ;==>FitWindow

; строка состояния под настройкой; отступ выравнивает её по подписи галочки
Func CreateStateLabel($iTop, $iIndent = 18)
	Local $idLabel = GUICtrlCreateLabel("", $g_iMargin + $iIndent, $iTop, $g_iContentWidth - $iIndent, $g_iLineHeight)
	GUICtrlSetBkColor($idLabel, $g_iColorPanel)
	Return $idLabel
EndFunc   ;==>CreateStateLabel

Func SetState($idLabel, $sText, $iColor)
	GUICtrlSetData($idLabel, $sText)
	GUICtrlSetColor($idLabel, $iColor)
EndFunc   ;==>SetState

; Красит подложку и убирает у неё два побочных эффекта:
; WS_CLIPSIBLINGS - чтобы при перерисовке она не затирала соседние элементы
; (без него у полей пропадали рамки, а картинки могли исчезнуть);
; без SS_NOTIFY статический элемент на проверку попадания отвечает
; "меня здесь нет", и мышь целиком проваливается к тому, что под ним.
Func Backdrop($idCtrl, $iColor)
	GUICtrlSetBkColor($idCtrl, $iColor)
	Local $hCtrl = GUICtrlGetHandle($idCtrl)
	Local $iStyle = _WinAPI_GetWindowLong($hCtrl, $GWL_STYLE)
	$iStyle = BitOR(BitAND($iStyle, BitNOT($SS_NOTIFY)), $WS_CLIPSIBLINGS)
	_WinAPI_SetWindowLong($hCtrl, $GWL_STYLE, $iStyle)
EndFunc   ;==>Backdrop

Func SetWindowIcon()
	Local $sIco = @TempDir & "\HotaPatcher_game.ico"
	FileInstall("Assets\Game.ico", $sIco, $FC_OVERWRITE)
	If FileExists($sIco) Then GUISetIcon($sIco, 0, $g_hGui)
EndFunc   ;==>SetWindowIcon

; FileInstall требует литерал в обоих аргументах, поэтому перечисление,
; а не имя переменной
Func LoadPicture($idPic, $sName)
	Local $sPath = @TempDir & "\HotaPatcher_" & $sName
	Switch $sName
		Case "Icon.png"
			FileInstall("Assets\Icon.png", $sPath, $FC_OVERWRITE)
		Case "Popup.png"
			FileInstall("Assets\Popup.png", $sPath, $FC_OVERWRITE)
		Case "Towns.png"
			FileInstall("Assets\Towns.png", $sPath, $FC_OVERWRITE)
	EndSwitch
	If Not FileExists($sPath) Then Return 0

	Local $hImage = _GDIPlus_ImageLoadFromFile($sPath)
	Local $hBitmap = 0
	If $hImage Then
		; альфа-канал PNG блендим в цвет фона окна, иначе GDI+ зальёт его чёрным
		$hBitmap = _GDIPlus_BitmapCreateHBITMAPFromBitmap($hImage, BitOR(0xFF000000, $g_iColorBg))
		_GDIPlus_ImageDispose($hImage)
	EndIf
	FileDelete($sPath)
	If Not $hBitmap Then Return 0

	Local $hPrevious = GUICtrlSendMsg($idPic, $STM_SETIMAGE, $IMAGE_BITMAP, $hBitmap)
	If $hPrevious Then _WinAPI_DeleteObject($hPrevious)
	Return $hBitmap
EndFunc   ;==>LoadPicture

Func Cleanup()
	For $i = 0 To UBound($g_ahBitmaps) - 1
		If $g_ahBitmaps[$i] Then _WinAPI_DeleteObject($g_ahBitmaps[$i])
	Next
	FileDelete(@TempDir & "\HotaPatcher_game.ico")
EndFunc   ;==>Cleanup

; ---------------------------------------------------------------- поиск папки

Func DetectGameDir()
	Local $sDir = RegistryGameDir()
	If DirIsGame($sDir) Then
		$g_sAutoDir = $sDir   ; запомнили, чтобы написать, откуда она взялась
		Return $sDir
	EndIf

	If DirIsGame(@ScriptDir) Then Return @ScriptDir
	Return ""
EndFunc   ;==>DetectGameDir

Func RegistryGameDir()
	; обе разрядности: HKLM64 для x86-процесса, WOW6432Node для x64-процесса
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
			$sDir = StringRegExpReplace($sDir, "\\+$", "")
			If DirIsGame($sDir) Then Return $sDir
		WEnd
	Next
	Return ""
EndFunc   ;==>RegistryGameDir

Func BrowseForDir()
	Local $sCurrent = GUICtrlRead($g_idInput)
	If Not FileExists($sCurrent) Then $sCurrent = ""
	Local $sDir = FileSelectFolder("Укажите папку с установленной игрой Heroes 3 HotA", "", 0, $sCurrent)
	If @error Then Return
	GUICtrlSetData($g_idInput, StringRegExpReplace($sDir, "\\+$", ""))
	RefreshState()
EndFunc   ;==>BrowseForDir

; папка годится, только если на месте все три файла, которые мы правим
Func DirIsGame($sDir)
	If $sDir = "" Then Return False
	Local $aFiles = TargetFiles($sDir)
	For $i = 0 To UBound($aFiles) - 1
		If Not FileExists($aFiles[$i]) Then Return False
	Next
	Return True
EndFunc   ;==>DirIsGame

Func GameDir()
	Return StringStripWS(GUICtrlRead($g_idInput), 3)
EndFunc   ;==>GameDir

; -------------------------------------------------------------- состояние GUI

Func RefreshState()
	Local $sDir = GameDir()
	$g_sLastDir = GUICtrlRead($g_idInput)

	If Not DirIsGame($sDir) Then
		SetState($g_idPathState, "В указанной папке нет файлов игры", $g_iColorBad)
		ShowPatches(False, False)   ; не знаем состояния - не показываем и галочек
		SetState($g_idPopupState, "Состояние неизвестно", $g_iColorMuted)
		SetState($g_idTownsState, "Состояние неизвестно", $g_iColorMuted)
		UpdateButtons()
		Return
	EndIf

	If $sDir = $g_sAutoDir Then
		SetState($g_idPathState, "Путь найден в реестре установленных программ", $g_iColorMuted)
	Else
		SetState($g_idPathState, "Файлы игры на месте", $g_iColorMuted)
	EndIf

	ShowPatches(PopupPatched($sDir), TownsPatched($sDir))
	UpdateButtons()
EndFunc   ;==>RefreshState

; галочки и строки под ними всегда показывают то, что лежит в файлах игры
Func ShowPatches($bPopup, $bTowns)
	$g_bPopupOn = $bPopup
	$g_bTownsOn = $bTowns
	GUICtrlSetState($g_idPopup, $bPopup ? $GUI_CHECKED : $GUI_UNCHECKED)
	GUICtrlSetState($g_idTowns, $bTowns ? $GUI_CHECKED : $GUI_UNCHECKED)
	ShowPatchState($g_idPopupState, $bPopup)
	ShowPatchState($g_idTownsState, $bTowns)
EndFunc   ;==>ShowPatches

Func ShowPatchState($idLabel, $bOn)
	If $bOn Then
		SetState($idLabel, "✓  Патч установлен", $g_iColorOk)
	Else
		SetState($idLabel, "Патч не установлен", $g_iColorMuted)
	EndIf
EndFunc   ;==>ShowPatchState

; «Применить» доступна, только если отмеченное расходится с установленным
Func UpdateButtons()
	Local $bChanged = (GUICtrlRead($g_idPopup) = $GUI_CHECKED) <> $g_bPopupOn Or _
			(GUICtrlRead($g_idTowns) = $GUI_CHECKED) <> $g_bTownsOn

	If DirIsGame(GameDir()) And $bChanged Then
		GUICtrlSetState($g_idApply, $GUI_ENABLE)
	Else
		GUICtrlSetState($g_idApply, $GUI_DISABLE)
	EndIf
EndFunc   ;==>UpdateButtons

; ------------------------------------------------------------------- действия

; приводит файлы игры к тому состоянию, которое отмечено галочками
Func DoApply()
	Local $sDir = GameDir()
	Local $bPopup = (GUICtrlRead($g_idPopup) = $GUI_CHECKED)
	Local $bTowns = (GUICtrlRead($g_idTowns) = $GUI_CHECKED)
	Local $bPopupChanged = ($bPopup <> $g_bPopupOn)
	Local $bTownsChanged = ($bTowns <> $g_bTownsOn)

	Local $sError = ""
	If GameIsRunning() Then
		$sError = "Игра запущена, закройте её – файлы заняты"
	Else
		$sError = ApplyPatches($sDir, $bPopup, $bTowns)
		If $sError <> "" Then RestoreFromBackups($sDir)   ; не оставляем файлы на полпути
	EndIf

	RefreshState()   ; строки состояния пересчитываются по самим файлам игры

	; после полного отката файлы снова оригинальные, копии хранить незачем
	If $sError = "" And Not $g_bPopupOn And Not $g_bTownsOn Then DeleteBackups($sDir)

	; об ошибке пишем там, где пользователь ждал изменения
	If $sError <> "" Then
		If $bPopupChanged Then SetState($g_idPopupState, $sError, $g_iColorBad)
		If $bTownsChanged Then SetState($g_idTownsState, $sError, $g_iColorBad)
	EndIf
EndFunc   ;==>DoApply

; правит файлы игры; возвращает описание ошибки или пустую строку
Func ApplyPatches($sDir, $bPopup, $bTowns)
	If Not $bPopup And Not $bTowns Then Return RestoreFromBackups($sDir)

	Local $sError = EnsureBackups($sDir)
	If $sError <> "" Then Return $sError
	$sError = RestoreFromBackups($sDir)   ; патчим всегда от оригиналов
	If $sError <> "" Then Return $sError

	If $bTowns Then
		For $i = 0 To UBound($g_aExeNames) - 1
			$sError = PatchExe($sDir & "\" & $g_aExeNames[$i])
			If $sError <> "" Then Return $sError
		Next
		; врезка в dll общая: она же при необходимости обходит окно
		Return PatchDllStub($sDir & "\" & $g_sDllName, $bPopup)
	EndIf

	Return PatchDllPopupOnly($sDir & "\" & $g_sDllName)
EndFunc   ;==>ApplyPatches

; ------------------------------------------------------------ резервные копии

Func TargetFiles($sDir)
	Local $aFiles[3] = [$sDir & "\" & $g_sDllName, $sDir & "\" & $g_aExeNames[0], $sDir & "\" & $g_aExeNames[1]]
	Return $aFiles
EndFunc   ;==>TargetFiles

; копия делается один раз - пока файлы ещё оригинальные
Func EnsureBackups($sDir)
	Local $aFiles = TargetFiles($sDir)
	For $i = 0 To UBound($aFiles) - 1
		If FileExists($aFiles[$i] & ".bak") Then ContinueLoop
		If Not FileCopy($aFiles[$i], $aFiles[$i] & ".bak") Then _
				Return "Не удалось создать резервную копию " & ShortName($aFiles[$i]) & ".bak"
	Next
	Return ""
EndFunc   ;==>EnsureBackups

; после полного отката копии не нужны: файлы и так оригинальные
Func DeleteBackups($sDir)
	Local $aFiles = TargetFiles($sDir)
	Local $bDeleted = False
	For $i = 0 To UBound($aFiles) - 1
		If FileExists($aFiles[$i] & ".bak") And FileDelete($aFiles[$i] & ".bak") Then $bDeleted = True
	Next
	Return $bDeleted
EndFunc   ;==>DeleteBackups

; перебирает все файлы, даже если один не поддался: так меньше шансов
; остаться с наполовину пропатченной игрой. Вернёт первую ошибку
Func RestoreFromBackups($sDir)
	Local $aFiles = TargetFiles($sDir)
	Local $sError = ""
	For $i = 0 To UBound($aFiles) - 1
		If Not FileExists($aFiles[$i] & ".bak") Then ContinueLoop
		If FileCopy($aFiles[$i] & ".bak", $aFiles[$i], $FC_OVERWRITE) Then ContinueLoop
		If $sError = "" Then $sError = "Не удалось восстановить файл " & ShortName($aFiles[$i])
	Next
	Return $sError
EndFunc   ;==>RestoreFromBackups

; ------------------------------------------------------------ проверка патчей

; читаем только нужные байты: файлы игры весят десятки мегабайт,
; а состояние определяют полтора десятка байт

Func PopupPatched($sDir)
	Local $sPath = $sDir & "\" & $g_sDllName
	Local $sAt = ReadBytes($sPath, $g_iDllHookOffset, 6)
	If @error Then Return False
	If $sAt = $g_sDllJumpSkip Then Return True
	If $sAt <> $g_sDllJumpStub Then Return False

	; врезка ведёт в нашу секцию - смотрим, какая заглушка туда положена
	Local $iRaw = SectionRawByRva(ReadBytes($sPath, 0, $g_iPeHeaderSize), $g_iDllSectionRva)
	If $iRaw = 0 Then Return False
	Return ReadBytes($sPath, $iRaw, StringLen($g_sDllStubBoth) / 2) = $g_sDllStubBoth
EndFunc   ;==>PopupPatched

Func TownsPatched($sDir)
	Local $sExpected = $g_aExeHooks[0][2]
	Local $sAt = ReadBytes($sDir & "\" & $g_aExeNames[1], _
			HexToInt($g_aExeHooks[0][0]) - 0x400000, StringLen($sExpected) / 2)
	If @error Then Return False
	Return $sAt = $sExpected
EndFunc   ;==>TownsPatched

; ----------------------------------------------------------- наложение патчей

; ниже все функции возвращают описание ошибки или пустую строку

Func PatchExe($sPath)
	Local $sHex = ReadFileHex($sPath)
	If @error Then Return "Не удалось прочитать " & ShortName($sPath)

	Local $iRaw = AddSection($sHex, ".hpatch", 0x800, $g_iExeSectionRva)
	If $iRaw = 0 Then Return "Не удалось добавить секцию, версия игры отличается от ожидаемой"

	$sHex = PutBytes($sHex, $iRaw, $g_sExeCode)

	For $i = 0 To UBound($g_aExeHooks) - 1
		Local $iOffset = HexToInt($g_aExeHooks[$i][0]) - 0x400000
		Local $sOrig = $g_aExeHooks[$i][1]
		If BytesAt($sHex, $iOffset, StringLen($sOrig) / 2) <> $sOrig Then _
				Return "Код игры отличается от ожидаемого"
		$sHex = PutBytes($sHex, $iOffset, $g_aExeHooks[$i][2])
	Next

	Return WriteFileHex($sPath, $sHex)
EndFunc   ;==>PatchExe

Func PatchDllStub($sPath, $bSkipPopup)
	Local $sHex = ReadFileHex($sPath)
	If @error Then Return "Не удалось прочитать " & ShortName($sPath)

	Local $iRaw = AddSection($sHex, ".hpatch", 0x100, $g_iDllSectionRva)
	If $iRaw = 0 Then Return "Не удалось добавить секцию в " & $g_sDllName & ", версия мода отличается"

	If $bSkipPopup Then
		$sHex = PutBytes($sHex, $iRaw, $g_sDllStubBoth)
	Else
		$sHex = PutBytes($sHex, $iRaw, $g_sDllStubTowns)
	EndIf

	If BytesAt($sHex, $g_iDllHookOffset, 5) <> $g_sDllHookOrig Then _
			Return "Код HD-мода отличается от ожидаемого"
	$sHex = PutBytes($sHex, $g_iDllHookOffset, $g_sDllJumpStub)

	Return WriteFileHex($sPath, $sHex)
EndFunc   ;==>PatchDllStub

Func PatchDllPopupOnly($sPath)
	Local $sHex = ReadFileHex($sPath)
	If @error Then Return "Не удалось прочитать " & ShortName($sPath)
	If BytesAt($sHex, $g_iDllHookOffset, 5) <> $g_sDllHookOrig Then _
			Return "Код HD-мода отличается от ожидаемого"
	$sHex = PutBytes($sHex, $g_iDllHookOffset, $g_sDllJumpSkip)
	Return WriteFileHex($sPath, $sHex)
EndFunc   ;==>PatchDllPopupOnly

; ----------------------------------------------------------------- работа с PE

; добавляет секцию и возвращает её смещение в файле; 0 - если не получилось
Func AddSection(ByRef $sHex, $sName, $iSize, $iExpectedRva)
	Local $iPe = GetDword($sHex, 0x3C)
	If GetDword($sHex, $iPe) <> 0x00004550 Then Return 0

	Local $iCount = GetWord($sHex, $iPe + 6)
	Local $iOpt = $iPe + 24
	Local $iTable = $iOpt + GetWord($sHex, $iPe + 20)
	Local $iSecAlign = GetDword($sHex, $iOpt + 32)
	Local $iFileAlign = GetDword($sHex, $iOpt + 36)

	Local $iLast = $iTable + ($iCount - 1) * 40
	Local $iNewRva = AlignUp(GetDword($sHex, $iLast + 12) + GetDword($sHex, $iLast + 8), $iSecAlign)
	If $iNewRva <> $iExpectedRva Then Return 0

	; хватает ли в заголовке места под ещё одну запись
	Local $iFirstRaw = 0x7FFFFFFF
	For $i = 0 To $iCount - 1
		Local $iRaw = GetDword($sHex, $iTable + $i * 40 + 20)
		If $iRaw < $iFirstRaw Then $iFirstRaw = $iRaw
	Next
	Local $iFree = $iTable + $iCount * 40
	If $iFree + 40 > $iFirstRaw Then Return 0

	Local $iFileSize = StringLen($sHex) / 2
	Local $iNewRaw = AlignUp($iFileSize, $iFileAlign)
	Local $iNewRawSize = AlignUp($iSize, $iFileAlign)

	Local $sHeader = ""
	For $i = 1 To 8
		If $i <= StringLen($sName) Then
			$sHeader &= Hex(Asc(StringMid($sName, $i, 1)), 2)
		Else
			$sHeader &= "00"
		EndIf
	Next
	$sHeader &= IntToHexLE($iSize) & IntToHexLE($iNewRva) & IntToHexLE($iNewRawSize) & IntToHexLE($iNewRaw)
	$sHeader &= "0000000000000000" & "00000000" & IntToHexLE(0xE0000060)

	$sHex = PutBytes($sHex, $iFree, $sHeader)
	$sHex = PutBytes($sHex, $iPe + 6, StringLeft(IntToHexLE($iCount + 1), 4))
	$sHex = PutBytes($sHex, $iOpt + 56, IntToHexLE(AlignUp($iNewRva + $iSize, $iSecAlign)))

	$sHex &= StringRepeat("00", $iNewRaw - $iFileSize + $iNewRawSize)
	Return $iNewRaw
EndFunc   ;==>AddSection

Func SectionRawByRva($sHex, $iRva)
	Local $iPe = GetDword($sHex, 0x3C)
	Local $iCount = GetWord($sHex, $iPe + 6)
	Local $iTable = $iPe + 24 + GetWord($sHex, $iPe + 20)
	For $i = 0 To $iCount - 1
		If GetDword($sHex, $iTable + $i * 40 + 12) = $iRva Then Return GetDword($sHex, $iTable + $i * 40 + 20)
	Next
	Return 0
EndFunc   ;==>SectionRawByRva

; ---------------------------------------------------------------------- мелочи

; в сообщениях об ошибке хватает названия папки игры и файла в ней,
; весь путь от корня диска только мешает читать
Func ShortName($sPath)
	Local $aParts = StringSplit($sPath, "\")
	If $aParts[0] < 2 Then Return $sPath
	Return $aParts[$aParts[0] - 1] & "\" & $aParts[$aParts[0]]
EndFunc   ;==>ShortName

Func GameIsRunning()
	Return ProcessExists("h3hota HD.exe") Or ProcessExists("h3hota.exe")
EndFunc   ;==>GameIsRunning

Func AlignUp($iValue, $iAlign)
	Return Int(($iValue + $iAlign - 1) / $iAlign) * $iAlign
EndFunc   ;==>AlignUp

Func StringRepeat($sText, $iTimes)
	Local $s = ""
	For $i = 1 To $iTimes
		$s &= $sText
	Next
	Return $s
EndFunc   ;==>StringRepeat

Func BytesAt($sHex, $iOffset, $iCount)
	Return StringMid($sHex, $iOffset * 2 + 1, $iCount * 2)
EndFunc   ;==>BytesAt

Func PutBytes($sHex, $iOffset, $sBytes)
	Return StringLeft($sHex, $iOffset * 2) & $sBytes & StringMid($sHex, $iOffset * 2 + StringLen($sBytes) + 1)
EndFunc   ;==>PutBytes

Func GetDword($sHex, $iOffset)
	Local $s = BytesAt($sHex, $iOffset, 4)
	Return Dec(StringMid($s, 7, 2) & StringMid($s, 5, 2) & StringMid($s, 3, 2) & StringLeft($s, 2))
EndFunc   ;==>GetDword

Func GetWord($sHex, $iOffset)
	Local $s = BytesAt($sHex, $iOffset, 2)
	Return Dec(StringMid($s, 3, 2) & StringLeft($s, 2))
EndFunc   ;==>GetWord

Func IntToHexLE($iValue)
	Local $s = Hex($iValue, 8)
	Return StringMid($s, 7, 2) & StringMid($s, 5, 2) & StringMid($s, 3, 2) & StringLeft($s, 2)
EndFunc   ;==>IntToHexLE

Func HexToInt($sHex)
	Return Dec(StringReplace($sHex, "0X", ""))
EndFunc   ;==>HexToInt

; кусок файла шестнадцатеричной строкой
Func ReadBytes($sPath, $iOffset, $iCount)
	Local $hFile = FileOpen($sPath, $FO_READ + $FO_BINARY)
	If $hFile = -1 Then Return SetError(1, 0, "")
	FileSetPos($hFile, $iOffset, $FILE_BEGIN)
	Local $bData = FileRead($hFile, $iCount)
	FileClose($hFile)
	Return StringTrimLeft(String($bData), 2)
EndFunc   ;==>ReadBytes

Func ReadFileHex($sPath)
	Local $hFile = FileOpen($sPath, $FO_READ + $FO_BINARY)
	If $hFile = -1 Then Return SetError(1, 0, "")
	Local $bData = FileRead($hFile)
	FileClose($hFile)
	Return StringTrimLeft(String($bData), 2)
EndFunc   ;==>ReadFileHex

Func WriteFileHex($sPath, $sHex)
	Local $hFile = FileOpen($sPath, $FO_OVERWRITE + $FO_BINARY)
	If $hFile = -1 Then Return "Не удалось записать " & ShortName($sPath)
	FileWrite($hFile, Binary("0x" & $sHex))
	FileClose($hFile)
	Return ""
EndFunc   ;==>WriteFileHex

