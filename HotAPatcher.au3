#cs ----------------------------------------------------------------------------

	Патчер для Heroes 3: Horn of the Abyss (HotA 1.8.0 + HD mod 5.7 R33)

	Патч 1. Убирает окно «Турнирные правила», которое HD-мод показывает
	при каждом нажатии «Начать».

	Патч 2. Запоминает выбранные стартовые город, героя и бонус всех игроков
	и подставляет их на следующей случайной карте.

	Оба патча трогают только файлы игры и полностью откатываются
	восстановлением резервных копий, которые патчер делает сам.

#ce ----------------------------------------------------------------------------

#pragma compile(Out, #Build\HotAPatcher.exe)
#pragma compile(Icon, Assets\Game.ico)
#pragma compile(ProductName, HotAPatcher)
#pragma compile(FileDescription, Патчер для Heroes 3 HotA)
#pragma compile(FileVersion, 1.01.0.0)
#pragma compile(LegalCopyright, )
#pragma compile(x64, false)

#NoTrayIcon

#include <FileConstants.au3>
#include <GDIPlus.au3>
#include <GUIConstantsEx.au3>
#include <StaticConstants.au3>
#include <StringConstants.au3>
#include <WinAPIGdi.au3>
#include <WinAPISysWin.au3>
#include <WindowsConstants.au3>
#include "PatchData.au3"

Global Const $g_sTitle = "HotAPatcher 1.01"

; названия патчей: ими подписаны галочки, ими же помечаются сообщения
Global Const $g_sPopupName = "Не показывать «Турнирные правила» при запуске новой игры"
Global Const $g_sTownsName = "Запоминать настройки новой игры между сессиями"

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

; поля строки в таблице секций, которую собирает SectionTable
Global Const $g_iSecName = 0, $g_iSecRva = 1, $g_iSecVSize = 2, $g_iSecRaw = 3, $g_iSecRawSize = 4

Global $g_hGui
Global $g_idInput, $g_idBrowse, $g_idApply, $g_idCancel, $g_idPopup, $g_idTowns
Global $g_idPopupState, $g_idTownsState, $g_idPathState
; что реально установлено в игре сейчас
Global $g_bPopupOn = False, $g_bTownsOn = False
Global $g_sLastDir = "", $g_sAutoDir = ""
Global $g_ahBitmaps[3] = [0, 0, 0]

; окно поднимается только при обычном запуске: Tools\TestPatches.au3 подключает
; этот файл как библиотеку, и Main() ему не нужен
If @Compiled Or @ScriptName = "HotAPatcher.au3" Then Main()

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

	Local $idSubtitle = GUICtrlCreateLabel("Выберите, что применить к игре", $g_iMargin + 42, 37, 344, 18)
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
	$g_idCancel = GUICtrlCreateButton("Закрыть", $iRight - $g_iBtnWidth * 2 - 8, $iButtons, $g_iBtnWidth, $g_iBtnHeight)

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
			$sDir = TrimSlash($sDir)
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
	GUICtrlSetData($g_idInput, TrimSlash($sDir))
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

	; dll читается и просматривается один раз на оба патча: это самая дорогая
	; часть обновления, а место врезки в ней для обоих одно и то же
	Local $bPopup = False, $bTowns = False
	Local $sDll = ReadFileHex($sDir & "\" & $g_sDllName)
	If Not @error Then
		Local $iOffset = 0, $iHookRva = 0, $iContinueRva = 0, $iCallRva = 0
		If FindDllHook($sDll, $iOffset, $iHookRva, $iContinueRva, $iCallRva) Then
			$bPopup = PopupPatchedAt($sDll, $iOffset, $iHookRva, $iContinueRva)
			$bTowns = ExePatched($sDir) And DllStubStateAt($sDll, $iOffset, $iHookRva) = ""
		EndIf
	EndIf

	ShowPatches($bPopup, $bTowns)
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

	Busy(True)   ; патч занимает около полусекунды, и всё это время окно молчит

	Local $sError = ""
	If GameIsRunning() Then
		$sError = "Игра запущена, закройте её – файлы заняты"
	Else
		$sError = ApplyPatches($sDir, $bPopup, $bTowns)
		If $sError <> "" Then RestoreFromBackups($sDir)   ; не оставляем файлы на полпути
	EndIf

	RefreshState()   ; строки состояния пересчитываются по самим файлам игры
	Busy(False)

	; галочки могли остаться неотработанными и без явной ошибки: патч мог лечь
	; наполовину, поэтому итог сверяется с тем, что просили
	If $sError = "" And ($g_bPopupOn <> $bPopup Or $g_bTownsOn <> $bTowns) Then _
			$sError = Mismatch($sDir, $bPopup, $bTowns, $g_bTownsOn)

	; после полного отката файлы снова оригинальные, копии хранить незачем
	If $sError = "" And Not $g_bPopupOn And Not $g_bTownsOn Then DeleteBackups($sDir)

	; об ошибке пишем там, где пользователь ждал изменения
	If $sError <> "" Then
		If $bPopupChanged Then SetState($g_idPopupState, $sError, $g_iColorBad)
		If $bTownsChanged Then SetState($g_idTownsState, $sError, $g_iColorBad)
	EndIf
EndFunc   ;==>DoApply

; Курсор ожидания на время работы с файлами. Окно перерисовывается сразу:
; своей очереди сообщений патчер не качает, пока правит файлы, и без явной
; перерисовки нажатая кнопка так и осталась бы нарисованной обычной
Func Busy($bOn)
	If Not $bOn Then
		GUISetCursor(2, 0, $g_hGui)   ; кнопку обратно включит UpdateButtons, если есть что применять
		Return
	EndIf
	GUICtrlSetState($g_idApply, $GUI_DISABLE)
	GUISetCursor(15, 1, $g_hGui)
	_WinAPI_RedrawWindow($g_hGui, 0, 0, BitOR($RDW_ALLCHILDREN, $RDW_UPDATENOW))
EndFunc   ;==>Busy

; правит файлы игры; возвращает описание ошибки или пустую строку
Func ApplyPatches($sDir, $bPopup, $bTowns)
	If Not $bPopup And Not $bTowns Then Return RestoreFromBackups($sDir, True)

	Local $sError = EnsureBackups($sDir)
	If $sError <> "" Then Return $sError
	$sError = RestoreFromBackups($sDir)   ; патчим всегда от оригиналов
	If $sError <> "" Then Return $sError

	If $bTowns Then
		For $i = 0 To UBound($g_aExeNames) - 1
			$sError = PatchExe($sDir & "\" & $g_aExeNames[$i])
			If $sError <> "" Then Return $sError
		Next
		; заглушка в dll зовёт процедуру из секции exe, поэтому её адрес
		; берётся из уже пропатченного файла
		Local $iSave = ExeSaveProc($sDir & "\" & $g_aExeNames[1])
		If $iSave = 0 Then Return "В " & $g_aExeNames[1] & " не нашлась секция патча"
		Return PatchDllStub($sDir & "\" & $g_sDllName, $bPopup, $iSave)
	EndIf

	Return PatchDllPopupOnly($sDir & "\" & $g_sDllName)
EndFunc   ;==>ApplyPatches

; Называет, что именно разошлось с запрошенным. Патч мог лечь наполовину:
; секция добавилась, а врезка не встала - тогда причина видна по самим файлам
Func Mismatch($sDir, $bPopup, $bTowns, $bTownsNow)
	If $bTowns <> $bTownsNow Then
		If Not $bTowns Then Return "патч настроек остался в файлах игры"
		Local $sWhy = ""
		For $i = 0 To UBound($g_aExeNames) - 1
			$sWhy = ExePatchState($sDir & "\" & $g_aExeNames[$i])
			If $sWhy <> "" Then ExitLoop
		Next
		If $sWhy = "" Then $sWhy = DllStubState($sDir & "\" & $g_sDllName)
		If $sWhy = "" Then $sWhy = "причина не видна"
		Return "патч настроек не встал, " & $sWhy
	EndIf
	If Not $bPopup Then Return "патч окна остался в файлах игры"
	Return "патч окна не встал, окно всё так же показывается"
EndFunc   ;==>Mismatch

; ------------------------------------------------------------ резервные копии

Func TargetFiles($sDir)
	Local $aFiles[3] = [$sDir & "\" & $g_sDllName, $sDir & "\" & $g_aExeNames[0], $sDir & "\" & $g_aExeNames[1]]
	Return $aFiles
EndFunc   ;==>TargetFiles

; Несёт ли файл наш патч. Своя секция - главная метка, но патч окна обходится
; без неё, поэтому у dll смотрим ещё и саму врезку.
Func FilePatched($sPath)
	Local $sHead = ReadBytes($sPath, 0, $g_iPeHeaderSize)
	If @error Then Return False
	If SectionRawByName($sHead, ".hpatch") <> 0 Then Return True
	If StringRight($sPath, StringLen($g_sDllName)) <> $g_sDllName Then Return False

	Local $sHex = ReadFileHex($sPath)
	If @error Then Return False
	Local $iOffset = 0, $iHookRva = 0, $iContinueRva = 0, $iCallRva = 0
	If Not FindDllHook($sHex, $iOffset, $iHookRva, $iContinueRva, $iCallRva) Then Return False
	Return BytesAt($sHex, $iOffset, 1) = "E9"
EndFunc   ;==>FilePatched

; Копия нужна только там, где файл уже изменён нами: из неё и делается откат.
; Пока файл чистый, он сам себе оригинал, и копия рядом переписывается заново -
; иначе обновление игры или мода оставило бы копию от прошлой версии, а патч,
; который всегда накладывается от копии, молча откатил бы это обновление.
Func EnsureBackups($sDir)
	Local $aFiles = TargetFiles($sDir)
	For $i = 0 To UBound($aFiles) - 1
		Local $sBak = $aFiles[$i] & ".bak"

		If FilePatched($aFiles[$i]) Then
			; без копии оригинал уже не собрать: патч наложен, а взять его неоткуда
			If Not FileExists($sBak) Then _
					Return "Потеряна резервная копия " & ShortName($aFiles[$i]) & ".bak"
			ContinueLoop
		EndIf

		If Not FileCopy($aFiles[$i], $sBak, $FC_OVERWRITE) Then _
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

; Перебирает все файлы, даже если один не поддался: так меньше шансов
; остаться с наполовину пропатченной игрой. Вернёт первую ошибку.
; $bOnlyPatched оставляет в покое файлы, которых мы не меняли: копия рядом с
; чистым файлом может быть от прошлой версии, и откат к ней отменил бы обновление
Func RestoreFromBackups($sDir, $bOnlyPatched = False)
	Local $aFiles = TargetFiles($sDir)
	Local $sError = ""
	For $i = 0 To UBound($aFiles) - 1
		If Not FileExists($aFiles[$i] & ".bak") Then ContinueLoop
		If $bOnlyPatched And Not FilePatched($aFiles[$i]) Then ContinueLoop
		If FileCopy($aFiles[$i] & ".bak", $aFiles[$i], $FC_OVERWRITE) Then ContinueLoop
		If $sError = "" Then $sError = "Не удалось восстановить файл " & ShortName($aFiles[$i])
	Next
	Return $sError
EndFunc   ;==>RestoreFromBackups

; ------------------------------------------------------------ проверка патчей

; состояние патча в exe определяют полтора десятка байт, их и читаем;
; dll приходится читать целиком - место врезки в ней ищется по коду

; Врезку в dll ищет вызывающий: поиск по мегабайтам стоит дороже всех проверок
; вместе взятых, а нужен он и патчу окна, и патчу настроек
Func PopupPatchedAt($sHex, $iOffset, $iHookRva, $iContinueRva)
	If BytesAt($sHex, $iOffset, 1) <> "E9" Then Return False   ; врезки нет

	Local $iTarget = $iHookRva + 5 + GetSDword($sHex, $iOffset + 1)
	If $iTarget = $iContinueRva Then Return True   ; переход сразу мимо окна

	; врезка ведёт в нашу секцию - смотрим, какая заглушка туда положена:
	; окно пропускается только если она уходит на ту же штатную ветку
	Local $iRaw = SectionRawByRva($sHex, $iTarget)
	If $iRaw = 0 Then Return False
	; между головой и хвостом заглушки лежит адрес процедуры сохранения,
	; он свой у каждой сборки, поэтому сверяем только сам код вокруг него
	Local $iLead = Int(StringLen($g_sDllStubHead) / 2)
	Local $iTail = Int(StringLen($g_sDllStubTail) / 2)
	Local $iHead = $iLead + 4 + $iTail
	If BytesAt($sHex, $iRaw, $iLead) <> $g_sDllStubHead Then Return False
	If BytesAt($sHex, $iRaw + $iLead + 4, $iTail) <> $g_sDllStubTail Then Return False
	If BytesAt($sHex, $iRaw + $iHead, 1) <> "E9" Then Return False
	Return $iTarget + $iHead + 5 + GetSDword($sHex, $iRaw + $iHead + 1) = $iContinueRva
EndFunc   ;==>PopupPatchedAt

; обе exe несут наш патч и он цел; про dll спрашивают отдельно
Func ExePatched($sDir)
	For $i = 0 To UBound($g_aExeNames) - 1
		If ExePatchState($sDir & "\" & $g_aExeNames[$i]) <> "" Then Return False
	Next
	Return True
EndFunc   ;==>ExePatched

; Что не так с патчем в exe; пустая строка - всё на месте.
; Наличия секции мало: она могла лечь, а врезка не встать, поэтому адреса врезок
; берутся из переходов внутри самой секции и обе стороны сверяются друг с другом
Func ExePatchState($sPath)
	Return ExeStateOf("", $sPath, ShortName($sPath))
EndFunc   ;==>ExePatchState

; Работает и по готовому образу в памяти, и прямо по файлу: при проверке перед
; записью образ уже собран, а при опросе состояния тянуть мегабайты незачем
Func ExeStateOf($sHex, $sPath, $sName)
	Local $sHead = ($sHex <> "") ? $sHex : ReadBytes($sPath, 0, $g_iPeHeaderSize)
	If @error Then Return "не удалось прочитать " & $sName

	Local $iSecRva = SectionRvaByName($sHead, ".hpatch")
	If $iSecRva = 0 Then Return "в " & $sName & " нет секции с кодом патча"
	Local $iRaw = SectionRawByName($sHead, ".hpatch")

	; в начале секции лежит имя файла с настройками, по нему и узнаём свой код
	Local $iMark = 16
	If Peek($sHex, $sPath, $iRaw, $iMark) <> StringLeft($g_sExeCode, $iMark * 2) Then _
			Return "в секции " & $sName & " чужой код"

	For $i = 0 To UBound($g_aExeRelRefs) - 1
		Local $iOff = $g_aExeRelRefs[$i][0]
		Local $sHook = $g_aExeRelRefs[$i][1]
		Local $iBack = $iSecRva + $iOff + 4 + SDwordOf(Peek($sHex, $sPath, $iRaw + $iOff, 4))
		Local $iHookRva = $iBack - $g_aExeRelRefs[$i][2]

		Local $iHookRaw = RawByRva($sHead, $iHookRva)
		If $iHookRaw = 0 Then Return "врезка " & $sHook & " в " & $sName & " указывает в пустоту"
		Local $sAt = Peek($sHex, $sPath, $iHookRaw, 5)
		If StringLeft($sAt, 2) <> "E9" Then Return "врезка " & $sHook & " не встала в " & $sName
		If $iHookRva + 5 + SDwordOf(StringTrimLeft($sAt, 2)) <> $iSecRva + HookBlock($sHook) Then _
				Return "врезка " & $sHook & " в " & $sName & " ведёт не в секцию патча"
	Next
	Return ""
EndFunc   ;==>ExeStateOf

; кусок либо из готового образа, либо прямо из файла
Func Peek($sHex, $sPath, $iAt, $iCount)
	If $sHex <> "" Then Return BytesAt($sHex, $iAt, $iCount)
	Return ReadBytes($sPath, $iAt, $iCount)
EndFunc   ;==>Peek

Func HookBlock($sName)
	For $i = 0 To UBound($g_aExeHooks) - 1
		If $g_aExeHooks[$i][0] = $sName Then Return $g_aExeHooks[$i][4]
	Next
	Return 0
EndFunc   ;==>HookBlock

; Что не так с заглушкой в dll; пустая строка - всё на месте.
; Заглушку ставит только патч настроек: одному патчу окна хватает перехода
Func DllStubState($sPath)
	Local $sHex = ReadFileHex($sPath)
	If @error Then Return "не удалось прочитать " & ShortName($sPath)
	Return DllStubStateOf($sHex)
EndFunc   ;==>DllStubState

Func DllStubStateOf($sHex)
	Local $iOffset = 0, $iHookRva = 0, $iContinueRva = 0, $iCallRva = 0
	If Not FindDllHook($sHex, $iOffset, $iHookRva, $iContinueRva, $iCallRva) Then _
			Return "в " & $g_sDllName & " не найдено место врезки"
	Return DllStubStateAt($sHex, $iOffset, $iHookRva)
EndFunc   ;==>DllStubStateOf

; то же, но по уже найденной врезке
Func DllStubStateAt($sHex, $iOffset, $iHookRva)
	If BytesAt($sHex, $iOffset, 1) <> "E9" Then Return "врезка не встала в " & $g_sDllName

	Local $iTarget = $iHookRva + 5 + GetSDword($sHex, $iOffset + 1)
	Local $iSecRva = SectionRvaByName($sHex, ".hpatch")
	If $iSecRva = 0 Or $iTarget <> $iSecRva Then _
			Return "врезка в " & $g_sDllName & " ведёт мимо заглушки"

	Local $iRaw = SectionRawByRva($sHex, $iSecRva)
	Local $iLead = Int(StringLen($g_sDllStubHead) / 2)
	If BytesAt($sHex, $iRaw, $iLead) <> $g_sDllStubHead Or _
			BytesAt($sHex, $iRaw + $iLead + 4, Int(StringLen($g_sDllStubTail) / 2)) <> $g_sDllStubTail Then _
			Return "в секции " & $g_sDllName & " чужая заглушка"
	Return ""
EndFunc   ;==>DllStubStateAt

; ----------------------------------------------------------- наложение патчей

; ниже все функции возвращают описание ошибки или пустую строку

Func PatchExe($sPath)
	Local $sHex = ReadFileHex($sPath)
	If @error Then Return "Не удалось прочитать " & ShortName($sPath)
	Local $iBase = ImageBase($sHex)

	; всё, что зависит от сборки игры, ищем до того, как трогать файл
	Local $aHookRaw[UBound($g_aExeHooks)], $aHookVa[UBound($g_aExeHooks)]
	For $i = 0 To UBound($g_aExeHooks) - 1
		Local $iAt = FindSignature($sHex, $g_aExeHooks[$i][1])
		If $iAt < 0 Then Return "В " & ShortName($sPath) & " не найдена врезка " & $g_aExeHooks[$i][0]
		$aHookRaw[$i] = $iAt + $g_aExeHooks[$i][2]
		$aHookVa[$i] = $iBase + SectionRvaByRaw($sHex, $aHookRaw[$i])
	Next

	Local $iScen = FindSignature($sHex, $g_sScenarioSig)
	If $iScen < 0 Then Return "В " & ShortName($sPath) & " не найден указатель на сценарий"
	Local $iScenarioPtr = GetDword($sHex, $iScen + $g_iScenarioAt)

	Local $iSectionRva = 0
	Local $iRaw = AddSection($sHex, ".hpatch", 0x800, 0, $iSectionRva)
	If $iRaw = 0 Then Return "Не удалось добавить секцию в " & ShortName($sPath)

	Local $sCode = FixupExeCode($sHex, $iBase, $iSectionRva, $iScenarioPtr, $aHookVa)
	If @error Then Return "В " & ShortName($sPath) & " нет импорта " & $sCode
	$sHex = PutBytes($sHex, $iRaw, $sCode)

	For $i = 0 To UBound($g_aExeHooks) - 1
		Local $iTarget = $iBase + $iSectionRva + $g_aExeHooks[$i][4]
		$sHex = PutBytes($sHex, $aHookRaw[$i], "E9" & _
				IntToHexLE($iTarget - ($aHookVa[$i] + 5)) & _
				StringRepeat("90", $g_aExeHooks[$i][3] - 5))
	Next

	; кривой образ на диск не уходит: сверяемся до записи
	Local $sState = ExeStateOf($sHex, $sPath, ShortName($sPath))
	If $sState <> "" Then Return "Патч собран неверно, " & $sState

	Return WriteFileHex($sPath, $sHex)
EndFunc   ;==>PatchExe

; Переносит код секции на её фактический адрес и подставляет адреса игры.
; Код собран под $g_iExeSectionRva, а лечь может куда угодно, поэтому ссылки
; внутрь него сдвигаются, адреса игры берутся из этой сборки, а переходы
; обратно в игру считаются от найденных врезок.
; При ошибке ставит @error и возвращает имя ненайденной функции
Func FixupExeCode($sHex, $iBase, $iSectionRva, $iScenarioPtr, ByRef $aHookVa)
	Local $sCode = $g_sExeCode
	Local $iShift = $iSectionRva - $g_iExeSectionRva

	For $i = 0 To UBound($g_aExeSecRefs) - 1
		Local $iOff = $g_aExeSecRefs[$i]
		$sCode = PutBytes($sCode, $iOff, IntToHexLE(GetDword($sCode, $iOff) + $iShift))
	Next

	For $i = 0 To UBound($g_aExeGameRefs) - 1
		Local $sName = $g_aExeGameRefs[$i][1]
		Local $iAddr = $iScenarioPtr
		If $sName <> "ScenarioPtr" Then
			$iAddr = ImportSlotVa($sHex, $sName)
			If $iAddr = 0 Then Return SetError(1, 0, $sName)
		EndIf
		$sCode = PutBytes($sCode, $g_aExeGameRefs[$i][0], IntToHexLE($iAddr))
	Next

	For $i = 0 To UBound($g_aExeRelRefs) - 1
		Local $iSpot = $g_aExeRelRefs[$i][0]
		Local $iTarget = HookVa($g_aExeRelRefs[$i][1], $aHookVa) + $g_aExeRelRefs[$i][2]
		$sCode = PutBytes($sCode, $iSpot, _
				IntToHexLE($iTarget - ($iBase + $iSectionRva + $iSpot + 4)))
	Next
	Return $sCode
EndFunc   ;==>FixupExeCode

Func HookVa($sName, ByRef $aHookVa)
	For $i = 0 To UBound($g_aExeHooks) - 1
		If $g_aExeHooks[$i][0] = $sName Then Return $aHookVa[$i]
	Next
	Return 0
EndFunc   ;==>HookVa

; адрес процедуры сохранения внутри секции exe: её зовёт заглушка в dll
Func ExeSaveProc($sPath)
	Local $sHead = ReadBytes($sPath, 0, $g_iPeHeaderSize)
	If @error Then Return 0
	Local $iRva = SectionRvaByName($sHead, ".hpatch")
	If $iRva = 0 Then Return 0
	Return ImageBase($sHead) + $iRva + $g_iExeSaveProc
EndFunc   ;==>ExeSaveProc

Func PatchDllStub($sPath, $bSkipPopup, $iSaveProc)
	Local $sHex = ReadFileHex($sPath)
	If @error Then Return "Не удалось прочитать " & ShortName($sPath)

	Local $iOffset = 0, $iHookRva = 0, $iContinueRva = 0, $iCallRva = 0
	If Not FindDllHook($sHex, $iOffset, $iHookRva, $iContinueRva, $iCallRva) Then _
			Return "В " & $g_sDllName & " не найдено место врезки"
	If BytesAt($sHex, $iOffset, 1) <> "E8" Then _
			Return $g_sDllName & " уже изменён, нужен оригинал"

	Local $iSectionRva = 0
	Local $iRaw = AddSection($sHex, ".hpatch", 0x100, 0, $iSectionRva)
	If $iRaw = 0 Then Return "Не удалось добавить секцию в " & $g_sDllName

	; голова заглушки одна и та же, дальше расходится: с пропуском окна уходим
	; на штатную ветку, без него делаем вытесненный вызов и возвращаемся за врезку
	Local $sPrefix = $g_sDllStubHead & IntToHexLE($iSaveProc) & $g_sDllStubTail
	Local $iHead = Int(StringLen($sPrefix) / 2)
	Local $iAfter = $iSectionRva + $iHead
	Local $sStub = $sPrefix
	If $bSkipPopup Then
		$sStub &= "E9" & IntToHexLE($iContinueRva - ($iAfter + 5))
	Else
		$sStub &= "E8" & IntToHexLE($iCallRva - ($iAfter + 5))
		$sStub &= "E9" & IntToHexLE(($iHookRva + 5) - ($iAfter + 10))
	EndIf

	$sHex = PutBytes($sHex, $iRaw, $sStub)
	; ровно пять байт: вытесненный вызов столько и занимал, следующая инструкция цела
	$sHex = PutBytes($sHex, $iOffset, "E9" & IntToHexLE($iSectionRva - ($iHookRva + 5)))

	Local $sState = DllStubStateOf($sHex)
	If $sState <> "" Then Return "Патч собран неверно, " & $sState

	Return WriteFileHex($sPath, $sHex)
EndFunc   ;==>PatchDllStub

Func PatchDllPopupOnly($sPath)
	Local $sHex = ReadFileHex($sPath)
	If @error Then Return "Не удалось прочитать " & ShortName($sPath)

	Local $iOffset = 0, $iHookRva = 0, $iContinueRva = 0, $iCallRva = 0
	If Not FindDllHook($sHex, $iOffset, $iHookRva, $iContinueRva, $iCallRva) Then _
			Return "В " & $g_sDllName & " не найдено место врезки"
	If BytesAt($sHex, $iOffset, 1) <> "E8" Then _
			Return $g_sDllName & " уже изменён, нужен оригинал"

	$sHex = PutBytes($sHex, $iOffset, "E9" & IntToHexLE($iContinueRva - ($iHookRva + 5)))
	If $iHookRva + 5 + GetSDword($sHex, $iOffset + 1) <> $iContinueRva Then _
			Return "Патч собран неверно, переход в " & $g_sDllName & " ведёт не туда"
	Return WriteFileHex($sPath, $sHex)
EndFunc   ;==>PatchDllPopupOnly

; ------------------------------------------------- место врезки в HD_HOTA.dll

; Врезка не привязана к смещению в файле: она ищется по коду вокруг вытесняемого
; вызова, поэтому обновление HD-мода, двигающее код, патчу не мешает.
;   84 C0                 test al, al
;   0F 85 xx xx xx xx     jne <штатная ветка «стартовать без окна»>
;   E8 xx xx xx xx        call <подготовка окна>, сюда и врезаемся
;   8D 85 E8 FD FF FF     lea eax, [ebp - 0x218]
; Шаг допускает и E9, так что уже пропатченный файл находится тем же поиском.
; Возвращает True и заполняет смещение врезки в файле, её RVA, RVA штатной ветки
; и RVA вытесняемого вызова.
Func FindDllHook($sHex, ByRef $iOffset, ByRef $iHookRva, ByRef $iContinueRva, ByRef $iCallRva)
	$iOffset = 0
	; шаг задан парой байт, в шаблон он идёт перечислением: E8 либо E9
	Local $sStep = ""
	For $i = 1 To StringLen($g_sDllSigStep) Step 2
		$sStep &= ($sStep = "" ? "" : "|") & StringMid($g_sDllSigStep, $i, 2)
	Next
	Local $sPattern = $g_sDllSigHead & "[0-9A-Fa-f]{8}(?:" & $sStep & ")[0-9A-Fa-f]{8}" & $g_sDllSigTail
	Local $iLen = StringLen($g_sDllSigHead) + 18 + StringLen($g_sDllSigTail)

	Local $iFound = -1, $iPos = 1, $iStep = 0
	While 1
		; регулярка только находит кандидата, проверяют его те же побайтные сверки
		StringRegExp($sHex, $sPattern, $STR_REGEXPARRAYMATCH, $iPos)
		If @error Then ExitLoop
		Local $iStart = @extended - $iLen   ; @extended указывает сразу за совпадением
		$iPos = $iStart + 1

		; совпадение считается только на границе байта: в шестнадцатеричной
		; строке те же символы попадаются и со сдвигом на полбайта
		If Mod($iStart, 2) = 1 Then
			Local $iAt = Int(($iStart - 1) / 2)
			$iStep = StringInStr($g_sDllSigStep, BytesAt($sHex, $iAt + 8, 1), 2)
			If BytesAt($sHex, $iAt, 4) = $g_sDllSigHead And _
					$iStep > 0 And Mod($iStep, 2) = 1 And _
					BytesAt($sHex, $iAt + 13, 6) = $g_sDllSigTail Then
				If $iFound >= 0 Then Return False   ; двусмысленно, лучше не трогать
				$iFound = $iAt
			EndIf
		EndIf
	WEnd
	If $iFound < 0 Then Return False

	$iOffset = $iFound + 8
	$iHookRva = SectionRvaByRaw($sHex, $iOffset)
	If $iHookRva = 0 Then Return False
	$iContinueRva = $iHookRva + GetSDword($sHex, $iFound + 4)
	$iCallRva = $iHookRva + 5 + GetSDword($sHex, $iOffset + 1)
	Return True
EndFunc   ;==>FindDllHook

; ----------------------------------------------------------------- работа с PE

; Добавляет секцию и возвращает её смещение в файле; 0 - если не получилось.
; $iExpectedRva = 0 отключает сверку адреса: она нужна только там, где код секции
; собран под конкретный адрес. Найденный адрес отдаётся через $iNewRva.
Func AddSection(ByRef $sHex, $sName, $iSize, $iExpectedRva, ByRef $iNewRva)
	Local $iPe = GetDword($sHex, 0x3C)
	If GetDword($sHex, $iPe) <> 0x00004550 Then Return 0

	Local $iCount = GetWord($sHex, $iPe + 6)
	Local $iOpt = $iPe + 24
	Local $iTable = $iOpt + GetWord($sHex, $iPe + 20)
	Local $iSecAlign = GetDword($sHex, $iOpt + 32)
	Local $iFileAlign = GetDword($sHex, $iOpt + 36)

	Local $iLast = $iTable + ($iCount - 1) * 40
	$iNewRva = AlignUp(GetDword($sHex, $iLast + 12) + GetDword($sHex, $iLast + 8), $iSecAlign)
	If $iExpectedRva <> 0 And $iNewRva <> $iExpectedRva Then Return 0

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

	Local $sHeader = SectionNameHex($sName)
	$sHeader &= IntToHexLE($iSize) & IntToHexLE($iNewRva) & IntToHexLE($iNewRawSize) & IntToHexLE($iNewRaw)
	$sHeader &= "0000000000000000" & "00000000" & IntToHexLE(0xE0000060)

	$sHex = PutBytes($sHex, $iFree, $sHeader)
	$sHex = PutBytes($sHex, $iPe + 6, StringLeft(IntToHexLE($iCount + 1), 4))
	$sHex = PutBytes($sHex, $iOpt + 56, IntToHexLE(AlignUp($iNewRva + $iSize, $iSecAlign)))

	$sHex &= StringRepeat("00", $iNewRaw - $iFileSize + $iNewRawSize)
	Return $iNewRaw
EndFunc   ;==>AddSection

; Таблица секций: строка на секцию, поля по индексам $g_iSec*.
; Разбор заголовка один на всех, дальше по таблице ищут и по имени, и по адресу
Func SectionTable($sHex)
	Local $aNone[0][5]
	Local $iPe = GetDword($sHex, 0x3C)
	If GetDword($sHex, $iPe) <> 0x00004550 Then Return $aNone

	Local $iCount = GetWord($sHex, $iPe + 6)
	Local $iTable = $iPe + 24 + GetWord($sHex, $iPe + 20)
	Local $aSec[$iCount][5]
	For $i = 0 To $iCount - 1
		Local $iRow = $iTable + $i * 40
		$aSec[$i][$g_iSecName] = BytesAt($sHex, $iRow, 8)
		$aSec[$i][$g_iSecVSize] = GetDword($sHex, $iRow + 8)
		$aSec[$i][$g_iSecRva] = GetDword($sHex, $iRow + 12)
		$aSec[$i][$g_iSecRawSize] = GetDword($sHex, $iRow + 16)
		$aSec[$i][$g_iSecRaw] = GetDword($sHex, $iRow + 20)
	Next
	Return $aSec
EndFunc   ;==>SectionTable

; строка секции по имени; -1 - такой секции нет
Func SectionRow(ByRef $aSec, $sName)
	Local $sWant = SectionNameHex($sName)
	For $i = 0 To UBound($aSec) - 1
		If $aSec[$i][$g_iSecName] = $sWant Then Return $i
	Next
	Return -1
EndFunc   ;==>SectionRow

; смещение в файле по адресу в образе; 0 - адрес вне секций.
; размер берётся больший из двух: в памяти секция бывает длиннее, чем на диске
Func RawByRvaIn(ByRef $aSec, $iRva)
	For $i = 0 To UBound($aSec) - 1
		Local $iSize = $aSec[$i][$g_iSecVSize]
		If $aSec[$i][$g_iSecRawSize] > $iSize Then $iSize = $aSec[$i][$g_iSecRawSize]
		If $iRva >= $aSec[$i][$g_iSecRva] And $iRva < $aSec[$i][$g_iSecRva] + $iSize Then _
				Return $aSec[$i][$g_iSecRaw] + ($iRva - $aSec[$i][$g_iSecRva])
	Next
	Return 0
EndFunc   ;==>RawByRvaIn

; смещение секции в файле по её начальному адресу; 0 - такой секции нет
Func SectionRawByRva($sHex, $iRva)
	Local $aSec = SectionTable($sHex)
	For $i = 0 To UBound($aSec) - 1
		If $aSec[$i][$g_iSecRva] = $iRva Then Return $aSec[$i][$g_iSecRaw]
	Next
	Return 0
EndFunc   ;==>SectionRawByRva

; ---------------------------------------------------------- поиск по сигнатуре

; Ищет последовательность байт, где ?? - любой байт. Возвращает смещение в файле
; или -1, если совпадений не ровно одно: двусмысленную сигнатуру лучше не трогать.
; Регулярное выражение тут только быстрый локатор: решает по-прежнему побайтная
; сверка в SignatureAt, а перебор строки силами AutoIt на мегабайтах слишком дорог
; (полный проход StringInStr по exe игры - около 100 мс, регулярка - около 10)
Func FindSignature($sHex, $sSig)
	Local $sPattern = StringReplace($sSig, "??", "[0-9A-Fa-f]{2}")
	Local $iLen = StringLen($sSig)

	Local $iFound = -1, $iPos = 1
	While 1
		StringRegExp($sHex, $sPattern, $STR_REGEXPARRAYMATCH, $iPos)
		If @error Then ExitLoop
		Local $iStart = @extended - $iLen   ; @extended указывает сразу за совпадением
		$iPos = $iStart + 1

		; совпадение считается только на границе байта: в шестнадцатеричной
		; строке те же символы попадаются и со сдвигом на полбайта
		If Mod($iStart, 2) = 0 Then ContinueLoop
		Local $iAt = Int(($iStart - 1) / 2)
		If Not SignatureAt($sHex, $iAt, $sSig) Then ContinueLoop
		If $iFound >= 0 Then Return -1
		$iFound = $iAt
	WEnd
	Return $iFound
EndFunc   ;==>FindSignature

Func SignatureAt($sHex, $iAt, $sSig)
	Local $iLen = Int(StringLen($sSig) / 2)
	Local $sGot = BytesAt($sHex, $iAt, $iLen)
	If StringLen($sGot) < $iLen * 2 Then Return False
	For $i = 1 To $iLen * 2 Step 2
		Local $sWant = StringMid($sSig, $i, 2)
		If $sWant <> "??" And StringMid($sGot, $i, 2) <> $sWant Then Return False
	Next
	Return True
EndFunc   ;==>SignatureAt

; имя секции в заголовке - восемь байт, добитых нулями
Func SectionNameHex($sName)
	Local $sHex = ""
	For $i = 1 To 8
		If $i <= StringLen($sName) Then
			$sHex &= Hex(Asc(StringMid($sName, $i, 1)), 2)
		Else
			$sHex &= "00"
		EndIf
	Next
	Return $sHex
EndFunc   ;==>SectionNameHex

; смещение секции в файле по её имени; 0 - такой секции нет.
; хватает заголовка PE, весь файл читать незачем
Func SectionRawByName($sHex, $sName)
	Local $aSec = SectionTable($sHex)
	Local $iRow = SectionRow($aSec, $sName)
	Return ($iRow < 0) ? 0 : $aSec[$iRow][$g_iSecRaw]
EndFunc   ;==>SectionRawByName

Func SectionRvaByName($sHex, $sName)
	Local $aSec = SectionTable($sHex)
	Local $iRow = SectionRow($aSec, $sName)
	Return ($iRow < 0) ? 0 : $aSec[$iRow][$g_iSecRva]
EndFunc   ;==>SectionRvaByName

; адрес в образе по смещению в файле; 0 - смещение вне секций
Func SectionRvaByRaw($sHex, $iRaw)
	Local $aSec = SectionTable($sHex)
	For $i = 0 To UBound($aSec) - 1
		Local $iStart = $aSec[$i][$g_iSecRaw]
		If $iRaw >= $iStart And $iRaw < $iStart + $aSec[$i][$g_iSecRawSize] Then _
				Return $aSec[$i][$g_iSecRva] + ($iRaw - $iStart)
	Next
	Return 0
EndFunc   ;==>SectionRvaByRaw

Func RawByRva($sHex, $iRva)
	Local $aSec = SectionTable($sHex)
	Return RawByRvaIn($aSec, $iRva)
EndFunc   ;==>RawByRva

Func ImageBase($sHex)
	Return GetDword($sHex, GetDword($sHex, 0x3C) + 24 + 28)
EndFunc   ;==>ImageBase

Func ReadAsciiz($sHex, $iAt)
	Local $sText = ""
	For $i = 0 To 63
		Local $sByte = BytesAt($sHex, $iAt + $i, 1)
		If $sByte = "" Or $sByte = "00" Then ExitLoop
		$sText &= Chr(Dec($sByte))
	Next
	Return $sText
EndFunc   ;==>ReadAsciiz

; Адрес ячейки импорта kernel32 по имени функции; 0 - не нашлась.
; Код секции зовёт файловые функции через эти ячейки, а лежат они в каждой
; сборке по-своему, поэтому адреса берутся из таблицы импортов, а не из данных
Func ImportSlotVa($sHex, $sFunc)
	Local $iPe = GetDword($sHex, 0x3C)
	Local $iImport = GetDword($sHex, $iPe + 24 + 96 + 8)
	If $iImport = 0 Then Return 0
	; таблица секций нужна на каждое имя в импорте, поэтому разбирается один раз
	Local $aSec = SectionTable($sHex)
	Local $iAt = RawByRvaIn($aSec, $iImport)
	If $iAt = 0 Then Return 0

	While 1
		Local $iNameRva = GetDword($sHex, $iAt + 12)
		Local $iFirst = GetDword($sHex, $iAt + 16)
		If $iNameRva = 0 And $iFirst = 0 Then ExitLoop

		; имя вне секций читать нечем: без проверки ReadAsciiz пошёл бы от начала файла
		Local $iNameRaw = RawByRvaIn($aSec, $iNameRva)
		If $iNameRaw > 0 And StringLower(ReadAsciiz($sHex, $iNameRaw)) = "kernel32.dll" Then
			Local $iThunks = GetDword($sHex, $iAt)
			If $iThunks = 0 Then $iThunks = $iFirst
			Local $iRaw = RawByRvaIn($aSec, $iThunks)
			Local $i = 0
			While $iRaw > 0
				Local $iEntry = GetDword($sHex, $iRaw + $i * 4)
				If $iEntry = 0 Then ExitLoop
				; со взведённым старшим битом импорт идёт по номеру, имени нет.
				; сравниваем с десятичным: литерал 0x80000000 AutoIt считает
				; знаковым и превращает в отрицательное число
				If $iEntry < 2147483648 Then
					Local $iEntryRaw = RawByRvaIn($aSec, $iEntry)
					If $iEntryRaw > 0 And ReadAsciiz($sHex, $iEntryRaw + 2) = $sFunc Then _
							Return ImageBase($sHex) + $iFirst + $i * 4
				EndIf
				$i += 1
			WEnd
		EndIf
		$iAt += 20
	WEnd
	Return 0
EndFunc   ;==>ImportSlotVa

; ---------------------------------------------------------------------- мелочи

; в сообщениях об ошибке хватает названия папки игры и файла в ней,
; весь путь от корня диска только мешает читать
Func ShortName($sPath)
	Local $aParts = StringSplit($sPath, "\")
	If $aParts[0] < 2 Then Return $sPath
	Return $aParts[$aParts[0] - 1] & "\" & $aParts[$aParts[0]]
EndFunc   ;==>ShortName

; хвостовой слэш мешает склеивать путь, но у корня диска он часть пути
Func TrimSlash($sPath)
	Return StringRegExpReplace($sPath, "(?<!:)\\+$", "")
EndFunc   ;==>TrimSlash

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

; @error, если кусок не помещается: иначе он молча уехал бы в хвост строки
; и образ стал бы длиннее файла, из которого собран
Func PutBytes($sHex, $iOffset, $sBytes)
	If $iOffset < 0 Or $iOffset * 2 + StringLen($sBytes) > StringLen($sHex) Then Return SetError(1, 0, $sHex)
	Return StringLeft($sHex, $iOffset * 2) & $sBytes & StringMid($sHex, $iOffset * 2 + StringLen($sBytes) + 1)
EndFunc   ;==>PutBytes

Func GetDword($sHex, $iOffset)
	Return DwordOf(BytesAt($sHex, $iOffset, 4))
EndFunc   ;==>GetDword

Func DwordOf($s)
	Return Dec(StringMid($s, 7, 2) & StringMid($s, 5, 2) & StringMid($s, 3, 2) & StringLeft($s, 2))
EndFunc   ;==>DwordOf

Func SDwordOf($s)
	Local $iValue = DwordOf($s)
	If $iValue > 0x7FFFFFFF Then $iValue -= 0x100000000
	Return $iValue
EndFunc   ;==>SDwordOf

Func GetWord($sHex, $iOffset)
	Local $s = BytesAt($sHex, $iOffset, 2)
	Return Dec(StringMid($s, 3, 2) & StringLeft($s, 2))
EndFunc   ;==>GetWord

; относительные переходы в коде знаковые, а GetDword отдаёт беззнаковое
Func GetSDword($sHex, $iOffset)
	Return SDwordOf(BytesAt($sHex, $iOffset, 4))
EndFunc   ;==>GetSDword

; Int() обязателен: деление в AutoIt даёт Double, а Hex() от Double отдаёт
; куски его двоичного представления вместо самого числа
Func IntToHexLE($iValue)
	Local $s = Hex(Int($iValue), 8)
	Return StringMid($s, 7, 2) & StringMid($s, 5, 2) & StringMid($s, 3, 2) & StringLeft($s, 2)
EndFunc   ;==>IntToHexLE

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

