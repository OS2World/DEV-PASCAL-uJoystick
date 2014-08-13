Unit uJoystick;

{
************************************************************
*
* Datum:     27.10.2002
* Autor:     Ing. Wolfgang Draxler
* Kommentar: Zugriff auf den Joystick.
*            Nur getestet auf den Joystick "Predator SV 85"
*            von der Firma Trust. Die Unit speichert
*            sich den Minimal, Maximal und Center-Position ab
*            und berechnet dadurch die Byte-Position
* Aenderungen:
*
************************************************************
}

Interface

Uses BseDos, Os2Def, Classes;

const cJoystickAnz    = 2;                { Anzahl der Joysticks, abhaengig vom Treiber }
      cJoystickAnzBtn = 2;                { Anzahl der Buttons pro Joystick, abhaengig vom Treiber }

type tDigJoystickLCR = (joy_Left,joy_Center,joy_Right);

type tDigJoystick = Record
       PosByte : tPoint;                  { Position des Joysticks in einem Berich von 0..255 }
       DigX    : tDigJoystickLCR;         { X-Position in: joy_Left, joy_Center, joy_Right }
       DigY    : tDigJoystickLCR;         { Y-Position in: joy_Left, joy_Center, joy_Right }
     End;

type tJoystickStatus= Array[1.. cJoystickAnz] of Record
       Pos    : tPoint;                   { Aktuelle Position }
       Lower  : tPoint;                   { Minimalwert vom Joystick}
       Center : tPoint;                   { Mittelwert vom Joystick }
       Upper  : tPoint;                   { Maximalwert vom Joystick }
       Button : Array[1..cJoystickAnzBtn] of Record
         Press: Boolean;                  { Button auf dem Joystick gedrueckt }
         Count: LongWord;                 { Wieoft der Button gedrueckt worden ist. }
       End;
                      End;

Type
  tJoystick = Class(TObject)
    Private
      fGamePort   : HFILE;                { Handle zu Joystick }
      fOldPos     : tPoint;               { Alte Position vom Joystick }
      fStatus     : tJoystickStatus;      { Status-Variable }
      fTicks      : LongWord;             { Anzahl der Abfragen}
      Function getDigital(iJoy : Byte) : tDigJoystick;
    Public
      Constructor Create;
      Destructor Destroy;  override;
      Function ReadStatus    : Boolean;
      Function GetGameVersion: LongWord;

      Property Digital[iJoy : Byte] : tDigJoystick read getDigital;
    Published
      Property GamePortHandle : HFile           Read fGamePort;
      Property GameVersion    : LongWord        Read GetGameVersion;
      Property Status         : tJoystickStatus Read fStatus;
      Property Ticks          : LongWord        Read fTicks;
  End;

Implementation

type tGameStatus = Record
       Joystick    : Array[1..cJoystickAnz, 1..2] of Word;
       BtnCount    : Array[1..cJoystickAnz, 1..cJoystickAnzBtn] of Word;
       ButtonMask  : Byte;
       ButtonStatus: Byte;
       Ticks       : LongWord;
     End;

Const PORT_NAME                = 'GAME$';
      IOCTL_CAT_USER           = $080;
      GAME_GET_VERSION         = $001;
      GAME_GET_PARMS           = $002;
      GAME_SET_PARMS           = $003;
      GAME_GET_CALIB           = $004;
      GAME_SET_CALIB           = $005;
      GAME_GET_DIGSET          = $006;
      GAME_SET_DIGSET          = $007;
      GAME_GET_STATUS          = $010;
      GAME_GET_STATUS_BUTWAIT  = $011;
      GAME_GET_STATUS_SAMPWAIT = $012;
      GAME_PORT_GET            = $020;
      GAME_RESET_PORT          = $060;

      JOY_AX_BIT               = $001;
      JOY_AY_BIT               = $002;
      JOY_BX_BIT               = $004;
      JOY_BY_BIT               = $008;

      JOY_BUT_BIT : Array[1..cJoystickAnz, 1..cJoystickAnzBtn] of Word =
                      (($010, $020),($040,$080));

{      JOY_A_BITS                      = (JOY_AX_BIT OR JOY_AY_BIT);
      JOY_B_BITS                      = (JOY_BX_BIT OR JOY_BY_BIT);
      JOY_ALLPOS_BITS                 = (JOY_A_BITS OR JOY_B_BITS);
      JOY_ALL_BUTS                    = (JOY_BUT1_BIT OR JOY_BUT2_BIT OR JOY_BUT3_BIT OR JOY_BUT4_BIT); }


Function tJoystick.getDigital(iJoy : Byte) : tDigJoystick ;
{ Umwandeln der Position vom Joystick in ein
  Byte-Position und in "joy_Left", "joy_Center" und
  "joy_Right" }

  Function DigBerechnung(iBytePos : Byte) : tDigJoystickLCR;

  Begin
    Case iBytePos of
      0..95    : Result:=joy_Left;
      156..255 : Result:=joy_right;
      else       Result:=joy_center;
    End;
  End;

Begin
  fStatus[iJoy].Center.X:=(fStatus[iJoy].Lower.X + fStatus[iJoy].Upper.X) div 2;
  fStatus[iJoy].Center.Y:=(fStatus[iJoy].Lower.Y + fStatus[iJoy].Upper.Y) div 2;
  if (fStatus[iJoy].Center.X>0) and (fStatus[iJoy].Center.Y>0)
    then
      Begin
        Result.PosByte.X:= (128 / fStatus[iJoy].Center.X) * fStatus[iJoy].Pos.X;
        Result.PosByte.Y:= (128 / fStatus[iJoy].Center.Y) * fStatus[iJoy].Pos.Y;
        Result.DigX:=DigBerechnung(Result.PosByte.X);
        Result.DigY:=DigBerechnung(Result.PosByte.Y);
      End
    else FillChar(Result, sizeof(tDigJoystick), #0);
End;

Function tJoystick.GetGameVersion: LongWord;
{ Liefert die Joystick-Version }

Var Len : LongWord;
    rc  : APIRET;

Begin
  if fGamePort = 0
    then Result:=0
    else DosDevIOCTL(fGameport,
                       IOCTL_CAT_USER,
                       GAME_GET_VERSION,
                       NIL, 0, NIL,
                       Result,
                       4,
                       Len);
End;

Function tJoystick.ReadStatus : Boolean;
{ Liest den Status des Joysticks ein und berechnet die Variablen vom Object }

var GameStatus : tGameStatus;
    rc         : APIRET;
    Len        : LongWord;
    Cou1, Cou2 : Byte;

Begin
  if fGamePort = 0 then
    Begin   
      Result:=false;
      exit;
    End;
  Result:=DosDevIOCTL(fGameport,
                   IOCTL_CAT_USER,
                   GAME_PORT_GET,
                   NIL,
                   0,
                   NIL,
                   GameStatus,
                   SizeOf(tGameStatus),
                   Len) = 0;
  if Result then
    Begin
      fTicks := GameStatus.Ticks;
      for Cou1:=1 to cJoystickAnz do
        Begin
          fOldPos := fStatus[Cou1].Pos;
          fStatus[Cou1].Pos.X := (fOldPos.X + GameStatus.Joystick[Cou1,1]) div 2;
          fStatus[Cou1].Pos.Y := (fOldPos.Y + GameStatus.Joystick[Cou1,2]) div 2;
          for Cou2:=1 to cJoystickAnzBtn do
            Begin
              fStatus[Cou1].Button[Cou2].Press:=
                   (GameStatus.ButtonStatus and JOY_BUT_BIT[Cou1, Cou2]) = JOY_BUT_BIT[Cou1, Cou2];
              fStatus[Cou1].Button[Cou2].Count:=GameStatus.BtnCount[Cou1, Cou2]
            End;

          if (fStatus[Cou1].Center.X <> 0) and
             (fStatus[Cou1].Center.Y <> 0) then
            Begin
              if fStatus[Cou1].Pos.X < fStatus[Cou1].Lower.X  then
                fStatus[Cou1].Lower.X := fStatus[Cou1].Pos.X;
              if fStatus[Cou1].Pos.Y < fStatus[Cou1].Lower.Y  then
                fStatus[Cou1].Lower.Y := fStatus[Cou1].Pos.Y;

              if fStatus[Cou1].Pos.X > fStatus[Cou1].Upper.X  then
                fStatus[Cou1].Upper.X := fStatus[Cou1].Pos.X;
              if fStatus[Cou1].Pos.Y > fStatus[Cou1].Upper.Y  then
                fStatus[Cou1].Upper.Y := fStatus[Cou1].Pos.Y;
            End;

        End;
    End;
End;

Constructor tJoystick.Create;
{ Generieren des Objekts und Oeffnen des Joystick-Ports }

Var rc    : APIRET;
    Action: ULONG;
    Cou   : Byte;

Begin
  inherited Create;
  rc := DosOpen (PORT_NAME,
                 fGameport,     { Filehandle}
                 Action,        { action taken}
                 0,             { FileSize}
                 FILE_READONLY, { FileAttribute}
                 FILE_OPEN,     { OPEN_ACTION_CREATE_IF_NEW, (OpenFlag) }
                 OPEN_SHARE_DENYNONE OR OPEN_ACCESS_READONLY,
                 NIL);          {EABUF}
  if rc<>0 then fGameport :=0;

  FillChar(fStatus, sizeof(tJoystickStatus),#0);
  ReadStatus;
  ReadStatus;
  for Cou:=1 to cJoystickAnz do
    Begin
      fStatus[Cou].Center := fStatus[Cou].Pos;
      fStatus[Cou].Lower.X :=fStatus[Cou].Center.X div 10;
      fStatus[Cou].Lower.Y :=fStatus[Cou].Center.Y div 10;
      fStatus[Cou].Upper.X :=fStatus[Cou].Center.X * 2.2;
      fStatus[Cou].Upper.Y :=fStatus[Cou].Center.Y * 2.2;
    End;
End;


Destructor tJoystick.Destroy;
{ Schliessen des Porrs und zerst”ren des Objekts }

Begin
  if fGamePort <>0 then
    DosClose(fGamePort);
  inherited Destroy;
End;


{
type tGameCalib  = Array [1..4, 1..3] Of Word;

Var GameCalib : tGameCalib;
  FillChar(GameCalib, SizeOf(tGameCalib), #0);
  fJoystick.SetCalib(GameCalib);
Function tJoystick.SetCalib(iGameCalib : tGameCalib): Boolean;
Var Len : LongWord;
    rc  : APIRET;
Begin
  if fGamePort = 0
    then Result:=false
    else Result:=DosDevIOCtl(fGamePort,
                  IOCTL_CAT_USER,
                  GAME_SET_CALIB,
                  NIL, 0, NIL,
                  iGameCalib, sizeOf(tGameCalib),
                  Len) = 0;
End; }

Begin
End.