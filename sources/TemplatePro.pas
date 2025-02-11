// ***************************************************************************
//
// Copyright (c) 2016-2024 Daniele Teti
//
// https://github.com/danieleteti/templatepro
//
// ***************************************************************************
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// ***************************************************************************

unit TemplatePro;

interface

uses
  System.Generics.Collections,
  System.Classes,
  System.SysUtils,
  System.TypInfo,
  Data.DB,
  System.DateUtils,
  System.RTTI;

const
  TEMPLATEPRO_VERSION = '0.6.1';

type
  ETProException = class(Exception)

  end;

  ETProCompilerException = class(ETProException)

  end;

  ETProRenderException = class(ETProException)

  end;

  ETProDuckTypingException = class(ETProException)

  end;

  TIfThenElseIndex = record
    IfIndex, ElseIndex: Int64;
  end;

  TTokenType = (
    ttContent, ttInclude, ttFor, ttEndFor, ttIfThen, ttBoolExpression, ttElse, ttEndIf, ttStartTag, ttComment,
    ttContinue, ttLiteralString, ttEndTag, ttValue, ttFilterName, ttFilterParameter, ttLineBreak, ttSystemVersion, ttExit, ttEOF);
  const
    TOKEN_TYPE_DESCR: array [Low(TTokenType)..High(TTokenType)] of string =
      ('ttContent', 'ttInclude', 'ttFor', 'ttEndFor', 'ttIfThen', 'ttBoolExpression', 'ttElse', 'ttEndIf', 'ttStartTag', 'ttComment',
       'ttContinue', 'ttLiteralString', 'ttEndTag', 'ttValue', 'ttFilterName', 'ttFilterParameter', 'ttLineBreak', 'ttSystemVersion', 'ttExit', 'ttEOF');
  type
    TToken = packed record
      TokenType: TTokenType;
      Value1: String;
      Value2: String;
      Ref1, Ref2: Int64;
      class function Create(TokType: TTokenType; Value1: String; Value2: String; Ref1: Int64 = -1; Ref2: Int64 = -1): TToken; static;
      function TokenTypeAsString: String;
      function ToString: String;
      procedure SaveToBytes(const aBytes: TBinaryWriter);
      class function CreateFromBytes(const aBytes: TBinaryReader): TToken; static;
    end;

  TTokenWalkProc = reference to procedure(const Index: Integer; const Token: TToken);

  TTProTemplateFunction = function(const aValue: TValue; const aParameters: TArray<string>): TValue;
  TTProVariablesInfo = (viSimpleType, viObject, viDataSet, viListOfObject, viJSONObject, viIterable);
  TTProVariablesInfos = set of TTProVariablesInfo;

  TVarDataSource = class
  protected
    VarValue: TValue;
    VarOption: TTProVariablesInfos;
    constructor Create(const VarValue: TValue; const VarOption: TTProVariablesInfos);
  end;

  TTProVariables = class(TObjectDictionary<string, TVarDataSource>)
  public
    constructor Create;
  end;


  TTProCompiledTemplateGetValueEvent = reference to procedure(const DataSource, Members: string; var Value: TValue; var Handled: Boolean);

  ITProCompiledTemplate = interface
    ['{0BE04DE7-6930-456B-86EE-BFD407BA6C46}']
    function Render: String;
    procedure ForEachToken(const TokenProc: TTokenWalkProc);
    procedure ClearData;
    procedure SetData(const Name: String; Value: TValue); overload;
    procedure AddFilter(const FunctionName: string; const FunctionImpl: TTProTemplateFunction);
    procedure DumpToFile(const FileName: String);
    procedure SaveToFile(const FileName: String);
    function GetOnGetValue: TTProCompiledTemplateGetValueEvent;
    procedure SetOnGetValue(const Value: TTProCompiledTemplateGetValueEvent);
    property OnGetValue: TTProCompiledTemplateGetValueEvent read GetOnGetValue write SetOnGetValue;
  end;

  TTProCompiledTemplateEvent = reference to procedure(const TemplateProCompiledTemplate: ITProCompiledTemplate);

  TLoopStackItem = class
  protected
    DataSourceName: String;
    LoopExpression: String;
    FullPath: String;
    IteratorName: String;
    IteratorPosition: Integer;
    function IncrementIteratorPosition: Integer;
    constructor Create(DataSourceName: String; LoopExpression: String; FullPath: String; IteratorName: String);
  end;

  TTProCompiledTemplate = class(TInterfacedObject, ITProCompiledTemplate)
  private
    fTokens: TList<TToken>;
    fVariables: TTProVariables;
    fTemplateFunctions: TDictionary<string, TTProTemplateFunction>;
    fLoopsStack: TObjectList<TLoopStackItem>;
    fOnGetValue: TTProCompiledTemplateGetValueEvent;
    function PeekLoop: TLoopStackItem;
    procedure PopLoop;
    procedure PushLoop(const LoopStackItem: TLoopStackItem);
    function LoopStackIsEmpty: Boolean;
    function WalkThroughLoopStack(const VarName: String; out BaseVarName: String; out FullPath: String): Boolean;
    constructor Create(Tokens: TList<TToken>);
    procedure Error(const aMessage: String); overload;
    procedure Error(const aMessage: String; const Params: array of const); overload;
    function IsTruthy(const Value: TValue): Boolean;
    function GetVarAsString(const Name: string): string;
    function GetTValueVarAsString(const Value: TValue; const VarName: string = ''): String;
    function GetVarAsTValue(const aName: string): TValue;
    function GetDataSetFieldAsTValue(const aDataSet: TDataSet; const FieldName: String): TValue;
    function EvaluateIfExpressionAt(var Idx: UInt64): Boolean;
    function GetVariables: TTProVariables;
    procedure SplitVariableName(const VariableWithMember: String; out VarName, VarMembers: String);
    function ExecuteFilter(aFunctionName: string; aParameters: TArray<string>; aValue: TValue): TValue;
    procedure CheckParNumber(const aHowManyPars: Integer; const aParameters: TArray<string>); overload;
    procedure CheckParNumber(const aMinParNumber, aMaxParNumber: Integer; const aParameters: TArray<string>); overload;
    function GetPseudoVariable(const VarIterator: Integer; const PseudoVarName: String): TValue; overload;
    function IsAnIterator(const VarName: String; out DataSourceName: String; out CurrentIterator: TLoopStackItem): Boolean;
    function GetOnGetValue: TTProCompiledTemplateGetValueEvent;
    function EvaluateValue(var Idx: UInt64; out MustBeEncoded: Boolean): TValue;
    procedure SetOnGetValue(const Value: TTProCompiledTemplateGetValueEvent);
    procedure DoOnGetValue(const DataSource, Members: string; var Value: TValue; var Handled: Boolean);
  public
    destructor Destroy; override;
    function Render: String;
    procedure ForEachToken(const TokenProc: TTokenWalkProc);
    procedure ClearData;
    procedure SaveToFile(const FileName: String);
    class function CreateFromFile(const FileName: String): ITProCompiledTemplate;
    procedure SetData(const Name: String; Value: TValue); overload;
    procedure AddFilter(const FunctionName: string; const FunctionImpl: TTProTemplateFunction);
    procedure DumpToFile(const FileName: String);
    property OnGetValue: TTProCompiledTemplateGetValueEvent read GetOnGetValue write SetOnGetValue;
  end;

  TTProCompiler = class
  strict private
    function MatchStartTag: Boolean;
    function MatchEndTag: Boolean;
    function MatchVariable(var aIdentifier: string): Boolean;
    function MatchFilterParamValue(var aParamValue: string): Boolean;
    function MatchSymbol(const aSymbol: string): Boolean;
    function MatchSpace: Boolean;
    function MatchString(out aStringValue: string): Boolean;
    procedure InternalMatchFilter(lIdentifier: String; var lStartVerbatim: UInt64; const CurrToken: TTokenType; aTokens: TList<TToken>; const lRef2: Integer);
    function GetFunctionParameters: TArray<String>;
  private
    fInputString: string;
    fCharIndex: Int64;
    fCurrentLine: Integer;
    fEncoding: TEncoding;
    fCurrentFileName: String;
    procedure Error(const aMessage: string);
    function Step: Char;
    function CurrentChar: Char;
    function GetSubsequentText: String;
    procedure InternalCompileIncludedTemplate(const aTemplate: string; const aTokens: TList<TToken>; const aFileNameRefPath: String);
    procedure FixJumps(const aTokens: TList<TToken>);
    procedure Compile(const aTemplate: string; const aTokens: TList<TToken>; const aFileNameRefPath: String); overload;
  public
    function Compile(const aTemplate: string; const aFileNameRefPath: String = ''): ITProCompiledTemplate; overload;
    constructor Create(aEncoding: TEncoding = nil);
  end;

  ITProWrappedList = interface
    ['{C1963FBF-1E42-4E2A-A17A-27F3945F13ED}']
    function GetItem(const AIndex: Integer): TObject;
    procedure Add(const AObject: TObject);
    function Count: Integer;
    procedure Clear;
    function IsWrappedList: Boolean; overload;
    function ItemIsObject(const AIndex: Integer; out AValue: TValue): Boolean;
  end;

  TTProConfiguration = class sealed
  private
    class var fOnContextConfiguration: TTProCompiledTemplateEvent;
  protected
    class procedure RegisterHandlers(const TemplateProCompiledTemplate: ITProCompiledTemplate);
  public
    class property OnContextConfiguration: TTProCompiledTemplateEvent read fOnContextConfiguration write fOnContextConfiguration;
  end;



function HTMLEncode(s: string): string;
function HTMLSpecialCharsEncode(s: string): string;


implementation

uses
  System.StrUtils, System.IOUtils, System.NetEncoding, System.Math,
  JsonDataObjects, MVCFramework.Nullables;

const
  Sign = ['-','+'];
  Numbers = ['0'..'9'];
  SignAndNumbers = Sign + Numbers;
  IdenfierAllowedFirstChars = ['a' .. 'z', 'A' .. 'Z', '_', '@'];
  IdenfierAllowedChars = ['a' .. 'z', 'A' .. 'Z', '_'] + Numbers;
  ValueAllowedChars = IdenfierAllowedChars + [' ', '-', '+', '*', '.', '@', '/', '\']; // maybe a lot others
  START_TAG = '{{';
  END_TAG = '}}';

type
  TTProRTTIUtils = class sealed
  public
    class function GetProperty(AObject: TObject; const APropertyName: string): TValue;
  end;

  TTProDuckTypedList = class(TInterfacedObject, ITProWrappedList)
  private
    FObjectAsDuck: TObject;
    FObjType: TRttiType;
    FAddMethod: TRttiMethod;
    FClearMethod: TRttiMethod;
    FCountProperty: TRttiProperty;
    FGetItemMethod: TRttiMethod;
    FGetCountMethod: TRttiMethod;
  protected
    procedure Add(const AObject: TObject);
    procedure Clear;
    function ItemIsObject(const AIndex: Integer; out AValue: TValue): Boolean;
  public
    constructor Create(const AObjectAsDuck: TObject); overload;
    constructor Create(const AInterfaceAsDuck: IInterface); overload;

    function IsWrappedList: Boolean; overload;
    function Count: Integer;
    procedure GetItemAsTValue(const AIndex: Integer; out AValue: TValue);
    function GetItem(const AIndex: Integer): TObject;
    class function CanBeWrappedAsList(const AObjectAsDuck: TObject): Boolean; overload; static;
    class function CanBeWrappedAsList(const AObjectAsDuck: TObject; out AMVCList: ITProWrappedList): Boolean; overload; static;
    class function CanBeWrappedAsList(const AInterfaceAsDuck: IInterface): Boolean; overload; static;
    class function Wrap(const AObjectAsDuck: TObject): ITProWrappedList; static;
  end;

var
  GlContext: TRttiContext;

function WrapAsList(const AObject: TObject): ITProWrappedList;
begin
  Result := TTProDuckTypedList.Wrap(AObject);
end;


{ TParser }

procedure TTProCompiledTemplate.AddFilter(const FunctionName: string; const FunctionImpl: TTProTemplateFunction);
begin
  fTemplateFunctions.Add(FunctionName.ToLower, FunctionImpl);
end;

function TTProCompiledTemplate.GetDataSetFieldAsTValue(const aDataSet: TDataSet; const FieldName: String): TValue;
var
  lField: TField;
begin
  lField := aDataSet.FieldByName(FieldName);
  case lField.DataType of
    ftInteger: Result := lField.AsInteger;
    ftLargeint, ftAutoInc: Result := lField.AsLargeInt;
    ftString, ftWideString, ftMemo, ftWideMemo: Result := lField.AsWideString;
    else
      Error('Invalid data type for field "%s": %s', [FieldName, TRttiEnumerationType.GetName<TFieldType>(lField.DataType)]);
  end;
end;

function TTProCompiledTemplate.GetOnGetValue: TTProCompiledTemplateGetValueEvent;
begin
  Result := fOnGetValue;
end;

function TTProCompiledTemplate.GetPseudoVariable(const VarIterator: Integer; const PseudoVarName: String): TValue;
begin
  if PseudoVarName = '@@index' then
  begin
    Result := VarIterator + 1;
  end
  else if PseudoVarName = '@@odd' then
  begin
    Result := (VarIterator + 1) mod 2 > 0;
  end
  else if PseudoVarName = '@@even' then
  begin
    Result := (VarIterator + 1) mod 2 = 0;
  end
  else
  begin
    Result := TValue.Empty;
  end;
end;


function TTProCompiledTemplate.GetTValueVarAsString(const Value: TValue; const VarName: string): String;
var
  lIsObject: Boolean;
  lAsObject: TObject;
begin
  if Value.IsEmpty then
  begin
    Exit('');
  end;

  lIsObject := False;
  lAsObject := nil;
  if Value.IsObject then
  begin
    lIsObject := True;
    lAsObject := Value.AsObject;
  end;

  if lIsObject then
  begin
    if lAsObject is TField then
      Result := TField(Value.AsObject).AsString
    else if lAsObject is TJsonBaseObject then
      Result := TJsonBaseObject(lAsObject).ToJSON()
    else
      Result := lAsObject.ToString;
  end
  else
  begin
    if Value.TypeInfo.Kind = tkRecord then
    begin
      if Value.TypeInfo = TypeInfo(NullableInt32) then
      begin
        Result := Value.AsType<NullableInt32>.Value.ToString;
      end
      else if Value.TypeInfo = TypeInfo(NullableUInt32) then
      begin
        Result := Value.AsType<NullableInt32>.Value.ToString;
      end
      else if Value.TypeInfo = TypeInfo(NullableInt16) then
      begin
        Result := Value.AsType<NullableInt16>.Value.ToString;
      end
      else if Value.TypeInfo = TypeInfo(NullableUInt16) then
      begin
        Result := Value.AsType<NullableUInt16>.Value.ToString;
      end
      else if Value.TypeInfo = TypeInfo(NullableInt64) then
      begin
        Result := Value.AsType<NullableInt64>.Value.ToString;
      end
      else if Value.TypeInfo = TypeInfo(NullableUInt64) then
      begin
        Result := Value.AsType<NullableUInt64>.Value.ToString;
      end
      else if Value.TypeInfo = TypeInfo(NullableString) then
      begin
        Result := Value.AsType<NullableString>.Value;
      end
      else if Value.TypeInfo = TypeInfo(NullableCurrency) then
      begin
        Result := Value.AsType<NullableCurrency>.Value.ToString;
      end
      else if Value.TypeInfo = TypeInfo(NullableBoolean) then
      begin
        Result := Value.AsType<NullableBoolean>.Value.ToString;
      end
      else if Value.TypeInfo = TypeInfo(NullableTDate) then
      begin
        Result := DateToISO8601(Value.AsType<NullableTDate>.Value);
      end
      else if Value.TypeInfo = TypeInfo(NullableTTime) then
      begin
        Result := DateToISO8601(Value.AsType<NullableTTime>.Value);
      end
      else if Value.TypeInfo = TypeInfo(NullableTDateTime) then
      begin
        Result := DateToISO8601(Value.AsType<NullableTDateTime>.Value);
      end
      else
      begin
        raise ETProException.Create('Unsupported type for variable "' + VarName + '"');
      end;
    end
    else
    begin
      Result := Value.ToString;
    end;
  end;

end;

procedure TTProCompiledTemplate.CheckParNumber(const aMinParNumber, aMaxParNumber: Integer;
  const aParameters: TArray<string>);
var
  lParNumber: Integer;
begin
  lParNumber := Length(aParameters);
  if (lParNumber < aMinParNumber) or (lParNumber > aMaxParNumber) then
  begin
    if aMinParNumber = aMaxParNumber then
      Error(Format('Expected %d parameters, got %d' , [aMinParNumber, lParNumber]))
    else
      Error(Format('Expected from %d to %d parameters, got %d', [aMinParNumber, aMaxParNumber, lParNumber]));
  end;
end;

procedure TTProCompiler.InternalCompileIncludedTemplate(const aTemplate: string;
  const aTokens: TList<TToken>; const aFileNameRefPath: String);
var
  lCompiler: TTProCompiler;
begin
  lCompiler := TTProCompiler.Create(fEncoding);
  try
    lCompiler.Compile(aTemplate, aTokens, aFileNameRefPath);
    if aTokens[aTokens.Count - 1].TokenType <> ttEOF then
    begin
      Error('Included file ' + aFileNameRefPath + ' doesn''t terminate with EOF');
    end;
    aTokens.Delete(aTokens.Count - 1); // remove the EOF
  finally
    lCompiler.Free;
  end;
end;

procedure TTProCompiler.InternalMatchFilter(lIdentifier: String; var lStartVerbatim: UInt64; const CurrToken: TTokenType; aTokens: TList<TToken>; const lRef2: Integer);
var
  lFilterName: string;
  lFilterParamsCount: Integer;
  lFilterParams: TArray<String>;
  I: Integer;
begin
  lFilterName := '';
  lFilterParamsCount := -1; {-1 means "no filter applied to value"}
  if MatchSymbol('|') then
  begin
    if not MatchVariable(lFilterName) then
      Error('Invalid function name applied to variable or literal string "' + lIdentifier + '"');
    lFilterParams := GetFunctionParameters;
    lFilterParamsCount := Length(lFilterParams);
  end;

  if not MatchEndTag then
  begin
    Error('Expected end tag "' + END_TAG + '" near ' + GetSubsequentText);
  end;
  lStartVerbatim := fCharIndex;
  aTokens.Add(TToken.Create(CurrToken, lIdentifier, '', lFilterParamsCount, lRef2));

  //add function with params
  if not lFilterName.IsEmpty then
  begin
    aTokens.Add(TToken.Create(ttFilterName, lFilterName, '', lFilterParamsCount));
    if lFilterParamsCount > 0 then
    begin
      for I := 0 to lFilterParamsCount -1 do
      begin
        aTokens.Add(TToken.Create(ttFilterParameter, lFilterParams[I], ''));
      end;
    end;
  end;

end;

constructor TTProCompiler.Create(aEncoding: TEncoding = nil);
begin
  inherited Create;
  if aEncoding = nil then
    fEncoding := TEncoding.UTF8 { default encoding }
  else
    fEncoding := aEncoding;
end;

function TTProCompiler.CurrentChar: Char;
begin
  Result := fInputString.Chars[fCharIndex]
end;

function TTProCompiler.MatchEndTag: Boolean;
begin
  Result := MatchSymbol(END_TAG);
end;

function TTProCompiler.MatchVariable(var aIdentifier: string): Boolean;
var
  lTmp: String;
begin
  aIdentifier := '';
  lTmp := '';
  Result := False;
  if CharInSet(fInputString.Chars[fCharIndex], IdenfierAllowedFirstChars) then
  begin
    lTmp := fInputString.Chars[fCharIndex];
    Inc(fCharIndex);
    if lTmp = '@' then
    begin
      if fInputString.Chars[fCharIndex] = '@' then
      begin
        lTmp := '@@';
        Inc(fCharIndex);
      end;
    end;

    while CharInSet(fInputString.Chars[fCharIndex], IdenfierAllowedChars) do
    begin
      lTmp := lTmp + fInputString.Chars[fCharIndex];
      Inc(fCharIndex);
    end;
    Result := True;
    aIdentifier := lTmp;
  end;
  if Result then
  begin
    while MatchSymbol('.') do
    begin
      lTmp := '';
      if not MatchVariable(lTmp) then
      begin
        Error('Expected identifier after "' + aIdentifier + '" - got ' + GetSubsequentText);
      end;
      aIdentifier := aIdentifier + '.' + lTmp;
    end;
  end;
end;

function TTProCompiler.MatchFilterParamValue(var aParamValue: string): Boolean;
var
  lTmp: String;
begin
  lTmp := '';
  Result := False;
  if MatchString(aParamValue) then
  begin
    Result := True;
  end else if CharInSet(fInputString.Chars[fCharIndex], SignAndNumbers) then
  begin
    lTmp := fInputString.Chars[fCharIndex];
    Inc(fCharIndex);
    while CharInSet(fInputString.Chars[fCharIndex], Numbers) do
    begin
      lTmp := lTmp + fInputString.Chars[fCharIndex];
      Inc(fCharIndex);
    end;
    Result := True;
    aParamValue := lTmp.Trim;
  end;

//  if CharInSet(fInputString.Chars[fCharIndex], IdenfierAllowedChars) then
//  begin
//    while CharInSet(fInputString.Chars[fCharIndex], ValueAllowedChars) do
//    begin
//      lTmp := lTmp + fInputString.Chars[fCharIndex];
//      Inc(fCharIndex);
//    end;
//    Result := True;
//    aParamValue := lTmp.Trim;
//  end;
end;

function TTProCompiler.MatchSpace: Boolean;
begin
  Result := MatchSymbol(' ');
  while MatchSymbol(' ') do;
end;

function TTProCompiler.MatchStartTag: Boolean;
begin
  Result := MatchSymbol(START_TAG);
end;

function TTProCompiler.MatchString(out aStringValue: String): Boolean;
begin
  aStringValue := '';
  Result := MatchSymbol('"');
  if Result then
  begin
    while not MatchSymbol('"') do //no escape so far
    begin
      if CurrentChar = #0 then
      begin
        Error('Unclosed string at the end of file');
      end;
      aStringValue := aStringValue + CurrentChar;
      Step;
    end;
  end;
end;

function TTProCompiler.MatchSymbol(const aSymbol: string): Boolean;
var
  lSymbolIndex: Integer;
  lSavedCharIndex: Int64;
  lSymbolLength: Integer;
begin
  if aSymbol.IsEmpty then
    Exit(True);
  lSavedCharIndex := fCharIndex;
  lSymbolIndex := 0;
  lSymbolLength := Length(aSymbol);
  while (fInputString.Chars[fCharIndex] = aSymbol.Chars[lSymbolIndex]) and (lSymbolIndex < lSymbolLength) do
  begin
    Inc(fCharIndex);
    Inc(lSymbolIndex);
  end;
  Result := (lSymbolIndex > 0) and (lSymbolIndex = lSymbolLength);
  if not Result then
    fCharIndex := lSavedCharIndex;
end;

function TTProCompiler.Step: Char;
begin
  Inc(fCharIndex);
  Result := CurrentChar;
end;

function TTProCompiler.Compile(const aTemplate: string; const aFileNameRefPath: String): ITProCompiledTemplate;
var
  lTokens: TList<TToken>;
  lFileNameRefPath: string;
begin
  if aFileNameRefPath.IsEmpty then
  begin
    lFileNameRefPath := TPath.Combine(TPath.GetDirectoryName(GetModuleName(HInstance)), 'main.template');
  end
  else
  begin
    lFileNameRefPath := TPath.GetFullPath(aFileNameRefPath);
  end;
  fCurrentFileName := lFileNameRefPath;
  lTokens := TList<TToken>.Create;
  try
    Compile(aTemplate, lTokens, fCurrentFileName);
    FixJumps(lTokens);
    Result := TTProCompiledTemplate.Create(lTokens);
  except
    lTokens.Free;
    raise;
  end;
end;

procedure TTProCompiler.Compile(const aTemplate: string; const aTokens: TList<TToken>; const aFileNameRefPath: String);
var
  lForStatementCount: Integer;
  lIfStatementCount: Integer;
  lLastToken: TTokenType;
  lChar: Char;
  lVarName: string;
  lFuncName: string;
  lIdentifier: string;
  lIteratorName: string;
  lStartVerbatim: UInt64;
  lEndVerbatim: UInt64;
  lNegation: Boolean;
  lFuncParams: TArray<String>;
  lFuncParamsCount: Integer;
  I: Integer;
  lIncludeFileContent: string;
  lCurrentFileName: string;
  lStringValue: string;
  lRef2: Integer;
  lContentOnThisLine: Integer;
begin
  aTokens.Add(TToken.Create(ttSystemVersion, TEMPLATEPRO_VERSION, ''));
  lLastToken := ttEOF;
  lContentOnThisLine := 0;
  fCurrentFileName := aFileNameRefPath;
  fCharIndex := -1;
  fCurrentLine := 1;
  lIfStatementCount := -1;
  lForStatementCount := -1;
  fInputString := aTemplate;
  lStartVerbatim := 0;
  if fInputString.Length > 0 then
  begin
    Step;
  end
  else
  begin
    aTokens.Add(TToken.Create(ttEOF, '', ''));
    fCharIndex := 1; {doesnt' execute while}
  end;
  while fCharIndex <= fInputString.Length do
  begin
    lChar := CurrentChar;
    if lChar = #0 then //eof
    begin
      lEndVerbatim := fCharIndex;
      if lEndVerbatim - lStartVerbatim > 0 then
      begin
        lLastToken := ttContent;
        aTokens.Add(TToken.Create(lLastToken, fInputString.Substring(lStartVerbatim, lEndVerbatim - lStartVerbatim), ''));
      end;
      aTokens.Add(TToken.Create(ttEOF, '', ''));
      Break;
    end;

    if MatchSymbol(sLineBreak) then         {linebreak}
    begin
      lEndVerbatim := fCharIndex - Length(sLineBreak);
      if lEndVerbatim - lStartVerbatim > 0 then
      begin
        Inc(lContentOnThisLine);
        aTokens.Add(TToken.Create(ttContent, fInputString.Substring(lStartVerbatim, lEndVerbatim - lStartVerbatim), ''));
      end;
      lStartVerbatim := fCharIndex;
      if lLastToken = ttLineBreak then Inc(lContentOnThisLine);
      lLastToken := ttLineBreak;
      if lContentOnThisLine > 0 then
      begin
        aTokens.Add(TToken.Create(lLastToken, '', ''));
      end;
      Inc(fCurrentLine);
      lContentOnThisLine := 0;
    end else if MatchStartTag then         {starttag}
    begin
      lEndVerbatim := fCharIndex - Length(START_TAG);

      if lEndVerbatim - lStartVerbatim > 0 then
      begin
        lLastToken := ttContent;
        aTokens.Add(TToken.Create(lLastToken, fInputString.Substring(lStartVerbatim, lEndVerbatim - lStartVerbatim), ''));
      end;

      if CurrentChar = START_TAG[1] then
      begin
        lLastToken := ttContent;
        aTokens.Add(TToken.Create(lLastToken, START_TAG, ''));
        Inc(fCharIndex);
        lStartVerbatim := fCharIndex;
        Continue;
      end;

      if CurrentChar = ':' then //variable
      begin
        Step;
        if MatchVariable(lVarName) then {variable}
        begin
          if lVarName.IsEmpty then
            Error('Invalid variable name');
          lFuncName := '';
          lFuncParamsCount := -1; {-1 means "no filter applied to value"}
          lRef2 := IfThen(MatchSymbol('$'),1,-1); // {{value$}} means no escaping
          MatchSpace;
          if MatchSymbol('|') then
          begin
            MatchSpace;
            if not MatchVariable(lFuncName) then
              Error('Invalid function name applied to variable ' + lVarName);
            MatchSpace;
            lFuncParams := GetFunctionParameters;
            lFuncParamsCount := Length(lFuncParams);
            MatchSpace;
          end;

          if not MatchEndTag then
          begin
            Error('Expected end tag "' + END_TAG + '" near ' + GetSubsequentText);
          end;
          lStartVerbatim := fCharIndex;
          lLastToken := ttValue;
          aTokens.Add(TToken.Create(lLastToken, lVarName, '', lFuncParamsCount, lRef2));
          Inc(lContentOnThisLine);

          //add function with params
          if not lFuncName.IsEmpty then
          begin
            aTokens.Add(TToken.Create(ttFilterName, lFuncName, '', lFuncParamsCount));
            if lFuncParamsCount > 0 then
            begin
              for I := 0 to lFuncParamsCount -1 do
              begin
                aTokens.Add(TToken.Create(ttFilterParameter, lFuncParams[I], ''));
              end;
            end;
          end;
        end; //matchvariable
      end
      else
      begin
        if MatchSymbol('for') then {loop}
        begin
          if not MatchSpace then
            Error('Expected "space"');
          if not MatchVariable(lIteratorName) then
            Error('Expected iterator name after "for" - EXAMPLE: for iterator in iterable');
          if not MatchSpace then
            Error('Expected "space"');
          if not MatchSymbol('in') then
            Error('Expected "in" after "for" iterator');
          if not MatchSpace then
            Error('Expected "space"');
          if not MatchVariable(lIdentifier) then
            Error('Expected iterable "for"');
          MatchSpace;
          if not MatchEndTag then
            Error('Expected closing tag for "for"');

          // create another element in the sections stack
          Inc(lForStatementCount);
          lLastToken := ttFor;
          if lIdentifier = lIteratorName then
          begin
            Error('loop data source and its iterator cannot have the same name: ' + lIdentifier)
          end;
          aTokens.Add(TToken.Create(lLastToken, lIdentifier, lIteratorName));
          lStartVerbatim := fCharIndex;
        end else if MatchSymbol('endfor') then {endfor}
        begin
          if not MatchEndTag then
            Error('Expected closing tag');
          if lForStatementCount = -1 then
          begin
            Error('endfor without loop');
          end;
          lLastToken := ttEndFor;
          aTokens.Add(TToken.Create(lLastToken, '', ''));
          Dec(lForStatementCount);
          lStartVerbatim := fCharIndex;
        end else if MatchSymbol('continue') then {continue}
        begin
          lLastToken := ttContinue;
          aTokens.Add(TToken.Create(lLastToken, '', ''));
        end else if MatchSymbol('endif') then {endif}
        begin
          if lIfStatementCount = -1 then
          begin
            Error('"endif" without "if"');
          end;
          if not MatchEndTag then
          begin
            Error('Expected closing tag for "endif"');
          end;

          lLastToken := ttEndIf;
          aTokens.Add(TToken.Create(lLastToken, '', ''));

          Dec(lIfStatementCount);
          lStartVerbatim := fCharIndex;
        end else if MatchSymbol('if') then
        begin
          if not MatchSpace then
          begin
      			Error('Expected <space> after "if"');
          end;
          lNegation := MatchSymbol('!');
          MatchSpace;
          if not MatchVariable(lIdentifier) then
            Error('Expected identifier after "if"');
          lFuncParamsCount := -1; {lFuncParamsCount = -1 means "no filter applied"}
          lFuncName := '';
          if MatchSymbol('|') then
          begin
            MatchSpace;
            if not MatchVariable(lFuncName) then
              Error('Invalid function name applied to variable ' + lVarName);
            lFuncParams := GetFunctionParameters;
            lFuncParamsCount := Length(lFuncParams);
          end;
          MatchSpace;
          if not MatchEndTag then
            Error('Expected closing tag for "if"');
          if lNegation then
          begin
            lIdentifier := '!' + lIdentifier;
          end;
          lLastToken := ttIfThen;
          aTokens.Add(TToken.Create(lLastToken, '' {lIdentifier}, ''));
          Inc(lIfStatementCount);
          lStartVerbatim := fCharIndex;

          lLastToken := ttBoolExpression;
          aTokens.Add(TToken.Create(lLastToken, lIdentifier, '', lFuncParamsCount, -1 {no html escape}));

          //add function with params
          if not lFuncName.IsEmpty then
          begin
            aTokens.Add(TToken.Create(ttFilterName, lFuncName, '', lFuncParamsCount));
            if lFuncParamsCount > 0 then
            begin
              for I := 0 to lFuncParamsCount -1 do
              begin
                aTokens.Add(TToken.Create(ttFilterParameter, lFuncParams[I], ''));
              end;
            end;
          end;


        end else if MatchSymbol('else') then
        begin
          if not MatchEndTag then
            Error('Expected closing tag for "else"');

          lLastToken := ttElse;
          aTokens.Add(TToken.Create(lLastToken, '', ''));
          lStartVerbatim := fCharIndex;
        end
        else if MatchSymbol('include') then {include}
        begin
          if not MatchSpace then
            Error('Expected "space" after "include"');

          {In a future version we could implement a function call}
          if not MatchString(lStringValue) then
          begin
            Error('Expected string after "include"');
          end;

          MatchSpace;

          if not MatchEndTag then
            Error('Expected closing tag for "include"');

          // create another element in the sections stack
          try
            if TDirectory.Exists(aFileNameRefPath) then
            begin
              lCurrentFileName := TPath.GetFullPath(TPath.Combine(aFileNameRefPath, lStringValue));
            end
            else
            begin
              lCurrentFileName := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(aFileNameRefPath), lStringValue));
            end;
            lIncludeFileContent := TFile.ReadAllText(lCurrentFileName, fEncoding);
          except
            on E: Exception do
            begin
              Error('Cannot read "' + lStringValue + '"');
            end;
          end;
          Inc(lContentOnThisLine);
          InternalCompileIncludedTemplate(lIncludeFileContent, aTokens, lCurrentFileName);
          lStartVerbatim := fCharIndex;
        end
        else if MatchSymbol('exit') then {exit}
        begin
          lLastToken := ttExit;
          aTokens.Add(TToken.Create(lLastToken, '', ''));
          lLastToken := ttEOF;
          aTokens.Add(TToken.Create(lLastToken, '', ''));
          Break;
        end
        else if MatchString(lStringValue) then {string}
        begin
          lLastToken := ttLiteralString;
          Inc(lContentOnThisLine);
          lRef2 := IfThen(MatchSymbol('$'),1,-1); // {{value$}} means no escaping
          MatchSpace;
          InternalMatchFilter(lStringValue, lStartVerbatim, ttLiteralString, aTokens, lRef2);
        end
        else if MatchSymbol('#') then
        begin
          while not MatchEndTag do
          begin
            Step;
          end;
          lStartVerbatim := fCharIndex;
          lLastToken := ttComment; {will not added into compiled template}
        end
        else
        begin
          lIdentifier := GetSubsequentText;
          Error('Expected command, got "' + lIdentifier + '"');
        end;
      end;
    end
    else
    begin
      Step;
    end;
  end;
end;

function CapitalizeString(const s: string; const CapitalizeFirst: Boolean): string;
const
  ALLOWEDCHARS = ['a' .. 'z', '_'];
var
  index: Integer;
  bCapitalizeNext: Boolean;
begin
  bCapitalizeNext := CapitalizeFirst;
  Result := lowercase(s);
  if Result <> EmptyStr then
  begin
    for index := 1 to Length(Result) do
    begin
      if bCapitalizeNext then
      begin
        Result[index] := UpCase(Result[index]);
        bCapitalizeNext := False;
      end
      else if not CharInSet(Result[index], ALLOWEDCHARS) then
      begin
        bCapitalizeNext := True;
      end;
    end; // for
  end; // if
end;

procedure TTProCompiler.Error(const aMessage: string);
begin
  raise ETProCompilerException.CreateFmt('%s - at line %d in file %s', [aMessage, fCurrentLine, fCurrentFileName]);
end;

procedure TTProCompiler.FixJumps(const aTokens: TList<TToken>);
var
  lForInStack: TStack<UInt64>;
  lContinueStack: TStack<UInt64>;
  lIfStatementStack: TStack<TIfThenElseIndex>;
  I: UInt64;
  lToken: TToken;
  lForAddress: UInt64;
  lIfStackItem: TIfThenElseIndex;
  lCheckForUnbalancedPair: Boolean;
  lTmpContinueAddress: UInt64;
begin
  lCheckForUnbalancedPair := True;
  lForInStack := TStack<UInt64>.Create;
  try
    lContinueStack := TStack<UInt64>.Create;
    try
      lIfStatementStack := TStack<TIfThenElseIndex>.Create;
      try
        for I := 0 to aTokens.Count - 1 do
        begin
          case aTokens[I].TokenType of
            ttFor: begin
              if lContinueStack.Count > 0 then
              begin
                Error('Continue stack corrupted');
              end;
              lForInStack.Push(I);
            end;

            ttEndFor: begin
              {ttFor.Ref1 --> endfor}
              lForAddress := lForInStack.Pop;
              lToken := aTokens[lForAddress];
              lToken.Ref1 := I;
              aTokens[lForAddress] := lToken;

              {ttEndFor.Ref1 --> for}
              lToken := aTokens[I];
              lToken.Ref1 := lForAddress;
              aTokens[I] := lToken;

              {if there's a ttContinue (or more than one), it must jump to endfor}
              while lContinueStack.Count > 0 do
              begin
                lTmpContinueAddress := lContinueStack.Pop;
                lToken := aTokens[lTmpContinueAddress];
                lToken.Ref1 := I;
                aTokens[lTmpContinueAddress] := lToken;
              end;
            end;

            ttContinue: begin
              lContinueStack.Push(I);
            end;

            {ttIfThen.Ref1 points always to relative else (if present otherwise -1)}
            {ttIfThen.Ref2 points always to relative endif}

            ttIfThen: begin
              lIfStackItem.IfIndex := I;
              lIfStackItem.ElseIndex := -1; {-1 means: "there isn't ttElse"}
              lIfStatementStack.Push(lIfStackItem);
            end;
            ttElse: begin
              lIfStackItem := lIfStatementStack.Pop;
              lIfStackItem.ElseIndex := I;
              lIfStatementStack.Push(lIfStackItem);
            end;
            ttEndIf: begin
              lIfStackItem := lIfStatementStack.Pop;

              {fixup ifthen}
              lToken := aTokens[lIfStackItem.IfIndex];
              lToken.Ref2 := I; {ttIfThen.Ref2 points always to relative endif}
              lToken.Ref1 := lIfStackItem.ElseIndex; {ttIfThen.Ref1 points always to relative else (if present, otherwise -1)}
              aTokens[lIfStackItem.IfIndex] := lToken;

              {fixup else}
              if lIfStackItem.ElseIndex > -1 then
              begin
                lToken := aTokens[lIfStackItem.ElseIndex];
                lToken.Ref2 := I; {ttElse.Ref2 points always to relative endif}
                aTokens[lIfStackItem.ElseIndex] := lToken;
              end;
            end;
            ttExit: begin
              lCheckForUnbalancedPair := False;
            end;
          end;
        end; // for

        if lCheckForUnbalancedPair and (lIfStatementStack.Count > 0) then
        begin
          Error('Unbalanced "if" - expected "endif"');
        end;
        if lCheckForUnbalancedPair and (lForInStack.Count > 0) then
        begin
          Error('Unbalanced "for" - expected "endfor"');
        end;
      finally
        lIfStatementStack.Free;
      end;
    finally
      lContinueStack.Free;
    end;
  finally
    lForInStack.Free;
  end;
end;

function TTProCompiler.GetFunctionParameters: TArray<String>;
var
  lFuncPar: string;
begin
  Result := [];
  while MatchSymbol(',') do
  begin
    lFuncPar := '';
    MatchSpace;
    if not MatchFilterParamValue(lFuncPar) then
      Error('Expected function parameter');
    Result := Result + [lFuncPar];
    MatchSpace;
  end;
end;

function TTProCompiler.GetSubsequentText: String;
var
  I: Integer;
begin
  Result := CurrentChar;
  Step;
  I := 0;
  while (CurrentChar <> #0) and (CurrentChar <> END_TAG[1]) and (I<20) do
  begin
    Result := Result + CurrentChar;
    Step;
    Inc(I);
  end;
  Result := Result.QuotedString('"');
end;

procedure TTProCompiledTemplate.CheckParNumber(const aHowManyPars: Integer; const aParameters: TArray<string>);
begin
  CheckParNumber(aHowManyPars, aHowManyPars, aParameters);
end;

function TTProCompiledTemplate.ExecuteFilter(aFunctionName: string; aParameters: TArray<string>;
  aValue: TValue): TValue;
var
  lDateValue: TDateTime;
  lStrValue: string;
  lFunc: TTProTemplateFunction;
  lFormatSettings: TFormatSettings;
  procedure FunctionError(const ErrMessage: string);
  begin
    Error(Format('%s in function %s', [ErrMessage, aFunctionName]));
  end;
begin
  aFunctionName := lowercase(aFunctionName);
  if aFunctionName = 'gt' then
  begin
    if Length(aParameters) <> 1 then
      FunctionError('expected 1 parameter');
    Result := aValue.AsInt64 > StrToInt64(aParameters[0]);
  end
  else if aFunctionName = 'ge' then
  begin
    if Length(aParameters) <> 1 then
      FunctionError('expected 1 parameter');
    Result := aValue.AsInt64 >= StrToInt64(aParameters[0]);
  end
  else if aFunctionName = 'lt' then
  begin
    if Length(aParameters) <> 1 then
      FunctionError('expected 1 parameter');
    Result := aValue.AsInt64 < StrToInt64(aParameters[0]);
  end
  else if aFunctionName = 'le' then
  begin
    if Length(aParameters) <> 1 then
      FunctionError('expected 1 parameter');
    Result := aValue.AsInt64 <= StrToInt64(aParameters[0]);
  end
  else if aFunctionName = 'contains' then
  begin
    if Length(aParameters) <> 1 then
      FunctionError('expected 1 parameter');
    Result := aValue.AsString.Contains(aParameters[0]);
  end
  else if aFunctionName = 'contains_ignore_case' then
  begin
    if Length(aParameters) <> 1 then
      FunctionError('expected 1 parameter');
    Result := aValue.AsString.ToLowerInvariant.Contains(aParameters[0].ToLowerInvariant);
  end
  else if (aFunctionName = 'eq') or (aFunctionName = 'ne') then
  begin
    if Length(aParameters) <> 1 then
      FunctionError('expected 1 parameter');
    if aValue.IsType<String> then
      Result := aValue.AsString = aParameters[0]
    else if aValue.IsType<Int64> then
      Result := aValue.AsInt64 = StrToInt(aParameters[0])
    else if aValue.IsType<Integer> then
      Result := aValue.AsInteger = StrToInt64(aParameters[0])
    else if aValue.IsType<TDate> then
      Result := TDate(aValue.AsExtended) = TDate(StrToFloat(aParameters[0]))
    else
      FunctionError('Unsupported param type for "' + String(aValue.TypeInfo.Name) + '"');
    if aFunctionName = 'ne' then
    begin
      Result := not Result.AsBoolean;
    end;
  end
  else if aFunctionName = 'uppercase' then
  begin
    Result := UpperCase(aValue.AsString);
  end else if aFunctionName = 'lowercase' then
  begin
    Result := lowercase(aValue.AsString);
  end else if aFunctionName = 'capitalize' then
  begin
    Result := CapitalizeString(aValue.AsString, True);
  end else if aFunctionName = 'rpad' then
  begin
    if aValue.IsType<Integer> then
      lStrValue := aValue.AsInteger.ToString
    else if aValue.IsType<string> then
      lStrValue := aValue.AsString
    else
      FunctionError('Invalid parameter/s');

    CheckParNumber(1, 2, aParameters);
    if Length(aParameters) = 1 then
    begin
      Result := lStrValue.PadRight(aParameters[0].ToInteger);
    end
    else
    begin
      Result := lStrValue.PadRight(aParameters[0].ToInteger, aParameters[1].Chars[0]);
    end;
  end else if aFunctionName = 'lpad' then
  begin
    if aValue.IsType<Integer> then
      lStrValue := aValue.AsInteger.ToString
    else if aValue.IsType<string> then
      lStrValue := aValue.AsString
    else
      FunctionError('Invalid parameter/s');

    CheckParNumber(1, 2, aParameters);
    if Length(aParameters) = 1 then
    begin
      Result := lStrValue.PadLeft(aParameters[0].ToInteger);
    end
    else
    begin
      Result := lStrValue.PadLeft(aParameters[0].ToInteger, aParameters[1].Chars[0]);
    end;
  end else if aFunctionName = 'datetostr' then
  begin
    if aValue.IsEmpty then
    begin
      Result := '';
    end else if aValue.TryAsType<TDateTime>(lDateValue) then
    begin
      if Length(aParameters) = 0 then
      begin
        Result := DateToStr(lDateValue)
      end
      else
      begin
        CheckParNumber(1, aParameters);
        lFormatSettings.ShortDateFormat := aParameters[0];
        Result := DateToStr(lDateValue, lFormatSettings)
      end;
    end
    else
    begin
      FunctionError('Invalid date ' + aValue.AsString.QuotedString);
    end;
  end else if (aFunctionName = 'datetimetostr') or (aFunctionName = 'formatdatetime') then
  begin
    if aValue.IsEmpty then
    begin
      Result := '';
    end else if aValue.TryAsType<TDateTime>(lDateValue) then
    begin
      if Length(aParameters) = 0 then
        Result := DateTimeToStr(lDateValue)
      else
      begin
        CheckParNumber(1, aParameters);
        Result := FormatDateTime(aParameters[0], lDateValue);
      end;
    end
    else
    begin
      FunctionError('Invalid datetime ' + aValue.AsString.QuotedString);
    end;
  end else if aFunctionName = 'empty' then
  begin
    CheckParNumber(0, aParameters);
    Result := TValue.Empty;
  end else if fTemplateFunctions.TryGetValue(aFunctionName, lFunc) then
  begin
    Result := lFunc(aValue, aParameters);
  end
  else
  begin
    Error(Format('Unknown function [%s]', [aFunctionName]));
  end;
end;

function HTMLEncode(s: string): string;
begin
  Result := HTMLSpecialCharsEncode(s);
end;

function HTMLSpecialCharsEncode(s: string): string;
var
  I: Integer;
  r: string;
begin
  I := 1;
  while I <= Length(s) do
  begin
    r := '';
    case ord(s[I]) of
      Ord('>'):
        r := 'gt';
      Ord('<'):
        r := 'lt';
      160:
        r := 'nbsp';
      161:
        r := 'excl';
      162:
        r := 'cent';
      163:
        r := 'ound';
      164:
        r := 'curren';
      165:
        r := 'yen';
      166:
        r := 'brvbar';
      167:
        r := 'sect';
      168:
        r := 'uml';
      169:
        r := 'copy';
      170:
        r := 'ordf';
      171:
        r := 'laquo';
      172:
        r := 'not';
      173:
        r := 'shy';
      174:
        r := 'reg';
      175:
        r := 'macr';
      176:
        r := 'deg';
      177:
        r := 'plusmn';
      178:
        r := 'sup2';
      179:
        r := 'sup3';
      180:
        r := 'acute';
      181:
        r := 'micro';
      182:
        r := 'para';
      183:
        r := 'middot';
      184:
        r := 'cedil';
      185:
        r := 'sup1';
      186:
        r := 'ordm';
      187:
        r := 'raquo';
      188:
        r := 'frac14';
      189:
        r := 'frac12';
      190:
        r := 'frac34';
      191:
        r := 'iquest';
      192:
        r := 'Agrave';
      193:
        r := 'Aacute';
      194:
        r := 'Acirc';
      195:
        r := 'Atilde';
      196:
        r := 'Auml';
      197:
        r := 'Aring';
      198:
        r := 'AElig';
      199:
        r := 'Ccedil';
      200:
        r := 'Egrave';
      201:
        r := 'Eacute';
      202:
        r := 'Ecirc';
      203:
        r := 'Euml';
      204:
        r := 'Igrave';
      205:
        r := 'Iacute';
      206:
        r := 'Icirc';
      207:
        r := 'Iuml';
      208:
        r := 'ETH';
      209:
        r := 'Ntilde';
      210:
        r := 'Ograve';
      211:
        r := 'Oacute';
      212:
        r := 'Ocirc';
      213:
        r := 'Otilde';
      214:
        r := 'Ouml';
      215:
        r := 'times';
      216:
        r := 'Oslash';
      217:
        r := 'Ugrave';
      218:
        r := 'Uacute';
      219:
        r := 'Ucirc';
      220:
        r := 'Uuml';
      221:
        r := 'Yacute';
      222:
        r := 'THORN';
      223:
        r := 'szlig';
      224:
        r := 'agrave';
      225:
        r := 'aacute';
      226:
        r := 'acirc';
      227:
        r := 'atilde';
      228:
        r := 'auml';
      229:
        r := 'aring';
      230:
        r := 'aelig';
      231:
        r := 'ccedil';
      232:
        r := 'egrave';
      233:
        r := 'eacute';
      234:
        r := 'ecirc';
      235:
        r := 'euml';
      236:
        r := 'igrave';
      237:
        r := 'iacute';
      238:
        r := 'icirc';
      239:
        r := 'iuml';
      240:
        r := 'eth';
      241:
        r := 'ntilde';
      242:
        r := 'ograve';
      243:
        r := 'oacute';
      244:
        r := 'ocirc';
      245:
        r := 'otilde';
      246:
        r := 'ouml';
      247:
        r := 'divide';
      248:
        r := 'oslash';
      249:
        r := 'ugrave';
      250:
        r := 'uacute';
      251:
        r := 'ucirc';
      252:
        r := 'uuml';
      253:
        r := 'yacute';
      254:
        r := 'thorn';
      255:
        r := 'yuml';
    end;
    if r <> '' then
    begin
      s := s.Replace(s[I], '&' + r + ';');
      Inc(I, Length(r) + 1);
    end;
    Inc(I)
  end;
  Result := s;
end;

{ TToken }

class function TToken.Create(TokType: TTokenType; Value1, Value2: String; Ref1: Int64; Ref2: Int64): TToken;
begin
  Result.TokenType:= TokType;
  Result.Value1 := Value1;
  Result.Value2 := Value2;
  Result.Ref1 := Ref1;
  Result.Ref2 := Ref2;
end;

class function TToken.CreateFromBytes(const aBytes: TBinaryReader): TToken;
var
  //lSize: UInt32;
  lValue1Size: UInt32;
  lValue2Size: UInt32;
  lTokenAsByte: Byte;
begin
  {
    STORAGE FORMAT

    Bytes
    0:    Total record size as UInt32
    1:    Token Type as Byte
    2:    Value1 Size in bytes as UInt32
    3:    Value1 bytes
    4:    Value2 Size in bytes as UInt32
    5:    Value2 bytes
    6:    Ref1 (8 bytes) in bytes - Int64
    7:    Ref1 (8 bytes) in bytes - Int64
  }

  //lSize := aBytes.ReadUInt32;
  lTokenAsByte := aBytes.ReadByte;
  Result.TokenType := TTokenType(lTokenAsByte);
  lValue1Size := aBytes.ReadUInt32;
  Result.Value1 := TEncoding.Unicode.GetString(aBytes.ReadBytes(lValue1Size));

  lValue2Size := aBytes.ReadUInt32;
  Result.Value2 := TEncoding.Unicode.GetString(aBytes.ReadBytes(lValue2Size));

  Result.Ref1 := aBytes.ReadInt64;
  Result.Ref2 := aBytes.ReadInt64;
end;

procedure TToken.SaveToBytes(const aBytes: TBinaryWriter);
var
//  lSize: UInt32;
  lValue1Bytes: TArray<Byte>;
  lValue2Bytes: TArray<Byte>;
  lValue1Length: UInt32;
  lValue2Length: UInt32;
  lTokenAsByte: Byte;
begin

//  lSize :=
//    SizeOf(UInt32) + {total record size}
//    1 +  //Token Type as Byte
//    4 +  //Value1 Size in bytes as UInt32
//    Length(Value1) * SizeOf(Char) + //value1 bytes
//    4 +  //Value2 Size in bytes as UInt32
//    Length(Value2) * SizeOf(Char) + //value2 bytes
//    8 + //ref1
//    8;  //ref2
  //aBytes.Write(lSize);

  lTokenAsByte := Byte(TokenType);
  aBytes.Write(lTokenAsByte);

  lValue1Bytes := TEncoding.Unicode.GetBytes(Value1);
  lValue1Length := UInt16(Length(lValue1Bytes));
  aBytes.Write(lValue1Length);
  aBytes.Write(lValue1Bytes);

  lValue2Bytes := TEncoding.Unicode.GetBytes(Value2);
  lValue2Length := UInt16(Length(lValue2Bytes));
  aBytes.Write(lValue2Length);
  aBytes.Write(lValue2Bytes);

  aBytes.Write(Ref1);

  aBytes.Write(Ref2);
end;

function TToken.TokenTypeAsString: String;
begin
  Result := TOKEN_TYPE_DESCR[self.TokenType];
end;

function TToken.ToString: String;
begin
  Result := Format('%15s | Ref1: %8d | Ref2: %8d | Val1: %-20s| Val2: %-20s',[TokenTypeAsString, Ref1, Ref2, Value1, Value2]);
end;

{ TTProCompiledTemplate }

constructor TTProCompiledTemplate.Create(Tokens: TList<TToken>);
begin
  inherited Create;
  fLoopsStack := TObjectList<TLoopStackItem>.Create(True);
  fTokens := Tokens;
  fTemplateFunctions := TDictionary<string, TTProTemplateFunction>.Create;
  TTProConfiguration.RegisterHandlers(Self);
end;

class function TTProCompiledTemplate.CreateFromFile(
  const FileName: String): ITProCompiledTemplate;
var
  lBR: TBinaryReader;
  lTokens: TList<TToken>;
begin
  lBR := TBinaryReader.Create(TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone), nil, True);
  try
    lTokens := TList<TToken>.Create;
    try
      try
      while True do
      begin
        lTokens.Add(TToken.CreateFromBytes(lBR));
        if lTokens.Last.TokenType = ttEOF then
        begin
          Break;
        end;
      end;
      except
        on E: Exception do
        begin
          raise ETProRenderException.CreateFmt('Cannot load compiled template from [FILE: %s][CLASS: %s][MSG: %s] - consider to delete templates cache.',
            [FileName, E.ClassName, E.Message])
        end;
      end;
      Result := TTProCompiledTemplate.Create(lTokens);
    except
      lTokens.Free;
      raise;
    end;
  finally
    lBR.Free;
  end;
end;

destructor TTProCompiledTemplate.Destroy;
begin
  fLoopsStack.Free;
  fTemplateFunctions.Free;
  fTokens.Free;
  fVariables.Free;
  inherited;
end;

procedure TTProCompiledTemplate.DoOnGetValue(const DataSource, Members: string;
  var Value: TValue; var Handled: Boolean);
begin
  Handled := False;
  if Assigned(fOnGetValue) then
  begin
    fOnGetValue(DataSource, Members, Value, Handled);
  end;
end;

procedure TTProCompiledTemplate.DumpToFile(const FileName: String);
var
  lToken: TToken;
  lSW: TStreamWriter;
  lIdx: UInt64;
begin
  lSW := TStreamWriter.Create(FileName);
  try
    lIdx := 0;
    for lToken in fTokens do
    begin
      lSW.WriteLine('%5d %s', [lIdx, lToken.ToString]);
      Inc(lIdx);
    end;
  finally
    lSW.Free;
  end;
end;

procedure TTProCompiledTemplate.Error(const aMessage: String);
begin
  raise ETProRenderException.Create(aMessage) at ReturnAddress;
end;

procedure TTProCompiledTemplate.ForEachToken(
  const TokenProc: TTokenWalkProc);
var
  I: Integer;
begin
  for I := 0 to fTokens.Count - 1 do
  begin
    TokenProc(I, fTokens[I]);
  end;
end;

function TTProCompiledTemplate.Render: String;
var
  lIdx: UInt64;
  lBuff: TStringBuilder;
  lDataSourceName: string;
  lVariable: TVarDataSource;
  lWrapped: ITProWrappedList;
  lJumpTo: Integer;
  lVarName: string;
  lVarValue: TValue;
  lJArr: TJDOJsonArray;
  lJObj: TJDOJsonObject;
  lVarMember: string;
  lBaseVarName: string;
  lFullPath: string;
  lForLoopItem: TLoopStackItem;
  lJValue: TJsonDataValueHelper;
  lMustBeEncoded: Boolean;
  lSavedIdx: UInt64;
begin
  lBuff := TStringBuilder.Create;
  try
    lIdx := 0;
    while fTokens[lIdx].TokenType <> ttEOF do
    begin
      //Writeln(fTokens[lIdx].ToString);
      case fTokens[lIdx].TokenType of
        ttContent: begin
          lBuff.Append(fTokens[lIdx].Value1);
        end;
        ttFor: begin
          lForLoopItem := PeekLoop;
          if LoopStackIsEmpty or (lForLoopItem.LoopExpression <> fTokens[lIdx].Value1) then
          begin //push a new loop stack item
            SplitVariableName(fTokens[lIdx].Value1, lVarName, lVarMember);
            {lVarName maybe an iterator, so I've to walk the stack to know
             the real information about the iterator}
            if WalkThroughLoopStack(lVarName, lBaseVarName, lFullPath) then
            begin
              lFullPath := lFullPath + '.' + lVarMember;
              PushLoop(TLoopStackItem.Create(lBaseVarName, fTokens[lIdx].Value1, lFullPath, fTokens[lIdx].Value2));
            end
            else
            begin
              PushLoop(TLoopStackItem.Create(lVarName, fTokens[lIdx].Value1, lVarMember, fTokens[lIdx].Value2));
            end;
          end;
          lForLoopItem := PeekLoop;

          // Now, work with the stack head
          if GetVariables.TryGetValue(PeekLoop.DataSourceName, lVariable) then
          begin
            if lForLoopItem.FullPath.IsEmpty then
            begin
              if not (viIterable in lVariable.VarOption) then
              begin
                Error(Format('Cannot iterate over a not iterable object [%s]', [fTokens[lIdx].Value1]));
              end;
            end;

            if viDataSet in lVariable.VarOption then
            begin
              if lForLoopItem.IteratorPosition = -1 then
              begin
                TDataset(lVariable.VarValue.AsObject).First;
              end;

              if TDataset(lVariable.VarValue.AsObject).Eof then
              begin
                lIdx := fTokens[lIdx].Ref1; //skip to endfor
                Continue;
              end
            end else if viListOfObject in lVariable.VarOption then
            begin
              lWrapped := WrapAsList(lVariable.VarValue.AsObject);
              //if lVariable.VarIterator = lWrapped.Count - 1 then
              if lForLoopItem.IteratorPosition = lWrapped.Count - 1 then
              begin
                lIdx := fTokens[lIdx].Ref1; //skip to endif
                Continue;
              end
              else
              begin
                PeekLoop.IncrementIteratorPosition; // lVariable.VarIterator := lVariable.VarIterator + 1;
              end;
            end else if viJSONObject in lVariable.VarOption then
            begin
              lJObj := TJDOJsonObject(lVariable.VarValue.AsObject);
              lForLoopItem := PeekLoop;
              lJValue := lJObj.Path[lForLoopItem.FullPath];

              case lJValue.Typ of
                jdtNone: begin
                  lIdx := fTokens[lIdx].Ref1; //skip to endfor
                  Continue;
                end;

                jdtArray: begin
                  if  lForLoopItem.IteratorPosition = lJObj.Path[lForLoopItem.FullPath].ArrayValue.Count - 1 then
                  begin
                    lIdx := fTokens[lIdx].Ref1; //skip to endfor
                    Continue;
                  end
                  else
                  begin
                    lForLoopItem.IncrementIteratorPosition;
                  end;
                end;

                else
                begin
                  Error('Only JSON array can be iterated');
                end;
              end;
            end
            else
            begin
              Error('Iteration not allowed for "' + fTokens[lIdx].Value1 + '"');
            end;
          end
          else
          begin
            Error(Format('Unknown variable in for..in statement [%s]', [fTokens[lIdx].Value1]));
          end;
        end;
        ttEndFor: begin
          if LoopStackIsEmpty then
          begin
            raise ETProRenderException.Create('Inconsistent "endfor"');
          end;

          lForLoopItem := PeekLoop;
          lDataSourceName := lForLoopItem.DataSourceName;
          if GetVariables.TryGetValue(lDataSourceName, lVariable) then
          begin
            if viDataSet in lVariable.VarOption then
            begin
              TDataset(lVariable.VarValue.AsObject).Next;
              lForLoopItem.IteratorPosition := TDataset(lVariable.VarValue.AsObject).RecNo;
              if not TDataset(lVariable.VarValue.AsObject).Eof then
              begin
                lIdx := fTokens[lIdx].Ref1; //goto loop
                Continue;
              end
              else
              begin
                PopLoop;
              end;
            end
            else if viJSONObject in lVariable.VarOption then
            begin
              lJObj := TJDOJsonObject(lVariable.VarValue.AsObject);
              lJArr := lJObj.Path[lForLoopItem.FullPath];
              if lForLoopItem.IteratorPosition < lJArr.Count - 1 then
              begin
                lIdx := fTokens[lIdx].Ref1; //skip to loop
                Continue;
              end
              else
              begin
                PopLoop;
              end;
            end
            else if viListOfObject in lVariable.VarOption then
            begin
              lWrapped := TTProDuckTypedList.Wrap(lVariable.VarValue.AsObject);
              if lForLoopItem.IteratorPosition < lWrapped.Count - 1 then
              begin
                lIdx := fTokens[lIdx].Ref1; //skip to loop
                Continue;
              end
              else
              begin
                PopLoop;
              end;
            end;
          end;
        end;
        ttIfThen: begin
          lSavedIdx := lIdx;
          if EvaluateIfExpressionAt(lIdx) then
          begin
            //do nothing
          end
          else
          begin
            lIdx := lSavedIdx;
            if fTokens[lIdx].Ref1 > -1 then {there is an else}
            begin
              lJumpTo := fTokens[lIdx].Ref1 + 1;
              //jump to the statement "after" ttElse (if it is ttLineBreak, jump it)
              if fTokens[lJumpTo].TokenType <> ttLineBreak then
                lIdx := lJumpTo
              else
                lIdx := lJumpTo + 1;
              Continue;
            end;
            lIdx := fTokens[lIdx].Ref2; //jump to "endif"
            Continue;
          end;
        end;
        ttElse: begin
          //always jump to ttEndIf which it reference is at ttElse.Ref2
          lIdx := fTokens[lIdx].Ref2;
          Continue;
        end;
        ttEndIf, ttStartTag, ttEndTag: begin end;
        ttInclude:
        begin
          Error('Invalid token in RENDER phase: ttInclude');
        end;
        ttBoolExpression:
        begin
          Error('Token ttBoolExpression cannot be at first RENDER level, should be handled by ttIfThen TOKEN');
        end;
        ttValue, ttLiteralString: begin
          lVarValue := EvaluateValue(lIdx, lMustBeEncoded {must be encoded});
          if lMustBeEncoded {lRef2 = -1 // encoded} then
            lBuff.Append(HTMLEncode(lVarValue.ToString))
          else
            lBuff.Append(lVarValue.ToString);
          if lVarValue.IsObjectInstance then
          begin
            lVarValue.AsObject.Free;
          end;
        end;
        ttLineBreak: begin
          lBuff.AppendLine;
        end;
        ttSystemVersion: begin
          if fTokens[lIdx].Value1 <> TEMPLATEPRO_VERSION then
          begin
            Error('Compiled template has been compiled with a different version. Expected ' +  TEMPLATEPRO_VERSION + ' got ' + fTokens[lIdx].Value1);
          end;
        end;
        ttContinue: begin
          lIdx := fTokens[lIdx].Ref1;
          Continue;
        end;
        ttExit: begin
          //do nothing
        end
        else
        begin
          Error('Invalid token at index #' + lIdx.ToString + ': ' + fTokens[lIdx].TokenTypeAsString);
        end;
      end;
      Inc(lIdx);
    end;
    Result := lBuff.ToString;
  finally
    lBuff.Free;
  end;
end;

function TTProCompiledTemplate.GetVarAsString(const Name: string): string;
var
  lValue: TValue;
begin
  lValue := GetVarAsTValue(Name);
  Result := GetTValueVarAsString(lValue, Name);
end;

function TTProCompiledTemplate.GetVarAsTValue(const aName: string): TValue;
var
  lVariable: TVarDataSource;
  lHasMember: Boolean;
  lJPath: string;
  lDataSource: string;
  lIsAnIterator: Boolean;
  lJObj: TJDOJsonObject;
  lVarName: string;
  lVarMembers: string;
  lCurrentIterator: TLoopStackItem;
  lPJSONDataValue: TJsonDataValueHelper;
  lHandled: Boolean;
begin
  lCurrentIterator := nil;
  SplitVariableName(aName, lVarName, lVarMembers);
  lHasMember := not lVarMembers.IsEmpty;
  lIsAnIterator := IsAnIterator(lVarName, lDataSource, lCurrentIterator);

  if not lIsAnIterator then
  begin
    lDataSource := lVarName;
  end;

  if GetVariables.TryGetValue(lDataSource, lVariable) then
  begin
    if lVariable = nil then
    begin
      Exit(nil);
    end;
    if viDataSet in lVariable.VarOption then
    begin
      if lIsAnIterator then
      begin
        if lHasMember and lVarMembers.StartsWith('@@') then
        begin
          lCurrentIterator.IteratorPosition := TDataSet(lVariable.VarValue.AsObject).RecNo - 1;
          Result := GetPseudoVariable(lCurrentIterator.IteratorPosition, lVarMembers);
        end
        else
        begin
          if lVarMembers.IsEmpty then
          begin
            Error('Empty field name while reading from iterator "%s"', [lVarName]);
          end;
          Result := GetDataSetFieldAsTValue(TDataSet(lVariable.VarValue.AsObject), lVarMembers);
        end;
      end
      else
      begin
        { not an interator }
        if lHasMember then
        begin
          Result := GetDataSetFieldAsTValue(TDataSet(lVariable.VarValue.AsObject), lVarMembers);
        end
        else
        begin
          Result := lVariable.VarValue.AsObject;
        end;
      end;
    end
    else if viJSONObject in lVariable.VarOption then
    begin
      lJObj := TJDOJsonObject(lVariable.VarValue.AsObject);

      if lIsAnIterator then
      begin
        if lVarMembers.StartsWith('@@') then
        begin
          Result := GetPseudoVariable(lCurrentIterator.IteratorPosition, lVarMembers);
        end
        else
        begin
          lJPath := lCurrentIterator.FullPath;
          lPJSONDataValue := lJObj.Path[lJPath].ArrayValue[lCurrentIterator.IteratorPosition];
          if lPJSONDataValue.Typ in [jdtArray, jdtObject] then
          begin
            if not lVarMembers.IsEmpty then
              lPJSONDataValue := lPJSONDataValue.Path[lVarMembers];
            case lPJSONDataValue.Typ of
              jdtArray: begin
                Result := lPJSONDataValue.ArrayValue.ToJSON();
              end;
              jdtObject: begin
                Result := lPJSONDataValue.ObjectValue.ToJSON();
              end;
              else
                Result := lPJSONDataValue.Value;
            end;
          end
          else
          begin
            if lVarMembers.IsEmpty then
              Result := lPJSONDataValue.Value
            else
              Result := '';
          end;
        end;
      end
      else
      begin
        lJPath := aName.Remove(0, Length(lVarName) + 1);
        if lJPath.IsEmpty then
          Result := lJObj
        else
        begin
          lPJSONDataValue := lJObj.Path[lJPath];
          if lPJSONDataValue.Typ = jdtString then
          begin
            Result := lJObj.Path[lJPath].Value
          end
          else if lPJSONDataValue.Typ = jdtArray then
          begin
            Result := lPJSONDataValue.ArrayValue;
          end else if lPJSONDataValue.Typ = jdtObject then
          begin
            Result := lPJSONDataValue.ObjectValue;
          end
          else
            raise ETProRenderException.Create('Unknown type for path ' + lJPath);
        end;
      end;
    end
    else if viListOfObject in lVariable.VarOption then
    begin
      if lVarMembers.StartsWith('@@') then
      begin
        Result := GetPseudoVariable(lCurrentIterator.IteratorPosition, lVarMembers);
      end
      else
      begin
        if lIsAnIterator then
        begin
          if lHasMember then
            Result := TTProRTTIUtils.GetProperty(WrapAsList(lVariable.VarValue.AsObject).GetItem(lCurrentIterator.IteratorPosition), lVarMembers)
          else
            Result := WrapAsList(lVariable.VarValue.AsObject).GetItem(lCurrentIterator.IteratorPosition);
        end
        else
        begin
          if lHasMember then
            Error(lDataSource + ' can be used only with filters or iterated using its alias')
          else
          begin
            Result := lVariable.VarValue.AsObject;
          end;
        end;
      end;
    end
    else if viObject in lVariable.VarOption then
    begin
      if lHasMember then
        Result := TTProRTTIUtils.GetProperty(lVariable.VarValue.AsObject, lVarMembers)
      else
        Result := lVariable.VarValue;
    end
    else if viSimpleType in lVariable.VarOption then
    begin
      if lVariable.VarValue.IsEmpty then
      begin
        Result := TValue.Empty;
      end
      else
      begin
        Result := lVariable.VarValue;
      end;
    end;
  end
  else
  begin
    DoOnGetValue(lDataSource, lVarMembers, Result, lHandled);
    if not lHandled then
    begin
      Result := TValue.Empty;
    end;
  end;
end;

function TTProCompiledTemplate.GetVariables: TTProVariables;
begin
  if not Assigned(fVariables) then
  begin
    fVariables := TTProVariables.Create;
  end;
  Result := fVariables;
end;

function TTProCompiledTemplate.IsAnIterator(const VarName: String; out DataSourceName: String; out CurrentIterator: TLoopStackItem): Boolean;
var
  I: Integer;
begin
  Result := False;
  if not LoopStackIsEmpty then {search datasource using current iterators stack}
  begin
    for I := fLoopsStack.Count - 1 downto 0 do
    begin
      if fLoopsStack[I].IteratorName = VarName then
      begin
        Result := True;
        DataSourceName := fLoopsStack[I].DataSourceName;
        CurrentIterator := fLoopsStack[I];
        Break;
      end;
    end;
  end;
end;

function TTProCompiledTemplate.IsTruthy(const Value: TValue): Boolean;
var
  lStrValue: String;
  lWrappedList: ITProWrappedList;
begin
  if Value.IsEmpty then
  begin
    Exit(False);
  end;
  lStrValue := Value.ToString;
  if Value.IsObjectInstance then
  begin
    if Value.AsObject = nil then
    begin
      lStrValue := '';
    end
    else if Value.AsObject is TDataSet then
    begin
      lStrValue := TDataSet(Value.AsObject).RecordCount.ToString;
    end
    else if Value.AsObject is TJsonArray then
    begin
      lStrValue := TJsonArray(Value.AsObject).Count.ToString;
    end
    else if Value.AsObject is TJsonObject then
    begin
      lStrValue := TJsonObject(Value.AsObject).Count.ToString;
    end
    else
    begin
      lWrappedList := TTProDuckTypedList.Wrap(Value.AsObject);
      if lWrappedList = nil then
      begin
        lStrValue := '';
      end
      else
      begin
        lStrValue := lWrappedList.Count.ToString;
      end;
    end;
  end;
  Result := not (SameText(lStrValue,'false') or SameText(lStrValue,'0') or SameText(lStrValue,''));
end;

function TTProCompiledTemplate.LoopStackIsEmpty: Boolean;
begin
  Result := fLoopsStack.Count = 0;
end;

function TTProCompiledTemplate.PeekLoop: TLoopStackItem;
begin
  if fLoopsStack.Count = 0 then
  begin
    Result := nil;
  end
  else
  begin
    Result := fLoopsStack.Last;
  end;
end;

procedure TTProCompiledTemplate.PopLoop;
begin
  fLoopsStack.Delete(fLoopsStack.Count - 1);
end;

procedure TTProCompiledTemplate.PushLoop(const LoopStackItem: TLoopStackItem);
begin
  fLoopsStack.Add(LoopStackItem);
end;

procedure TTProCompiledTemplate.Error(const aMessage: String;
  const Params: array of const);
begin
  Error(Format(aMessage, Params));
end;

//function TTProCompiledTemplate.EvaluateIfExpression(aIdentifier: string): Boolean;
//var
//  lVarValue: TValue;
//  lNegation: Boolean;
//  lVariable: TVarDataSource;
//  lTmp: Boolean;
//  lDataSourceName: String;
//  lHasMember: Boolean;
//  lList: ITProWrappedList;
//  lVarName, lVarMembers: String;
//  lCurrentIterator: TLoopStackItem;
//  lIsAnIterator: Boolean;
//  lHandled: Boolean;
//begin
//  lNegation := aIdentifier.StartsWith('!');
//  if lNegation then
//    aIdentifier := aIdentifier.Remove(0,1);
//
//  SplitVariableName(aIdentifier, lVarName, lVarMembers);
//
//  lHasMember := Length(lVarMembers) > 0;
//
//  lIsAnIterator := IsAnIterator(lVarName, lDataSourceName, lCurrentIterator);
//
//  if not lIsAnIterator then
//  begin
//    lDataSourceName := lVarName;
//  end;
//
//  if GetVariables.TryGetValue(lDataSourceName, lVariable) then
//  begin
//    if lVariable = nil then
//    begin
//      Exit(lNegation xor False);
//    end;
//    if viDataSet in lVariable.VarOption then
//    begin
//      if lHasMember then
//      begin
//        if lVarMembers.StartsWith('@@') then
//        begin
//          if not lIsAnIterator then
//          begin
//            Error('Pseudovariables (@@) can be used only on iterators');
//          end;
//          lVarValue := GetPseudoVariable(lCurrentIterator.IteratorPosition, lVarMembers);
//        end
//        else
//        begin
//          lVarValue := TValue.From<Variant>(TDataSet(lVariable.VarValue.AsObject).FieldByName(lVarMembers).Value);
//        end;
//        lTmp := IsTruthy(lVarValue);
//      end
//      else
//      begin
//        lTmp := not TDataSet(lVariable.VarValue.AsObject).Eof;
//      end;
//      Exit(lNegation xor lTmp);
//    end
//    else if viListOfObject in lVariable.VarOption then
//    begin
//      lList := WrapAsList(lVariable.VarValue.AsObject);
//      if lHasMember then
//      begin
//        if lVarMembers.StartsWith('@@') then
//        begin
//          lVarValue := GetPseudoVariable(lCurrentIterator.IteratorPosition, lVarMembers);
//        end
//        else
//        begin
//          lVarValue := TTProRTTIUtils.GetProperty(lList.GetItem(lCurrentIterator.IteratorPosition), lVarMembers);
//        end;
//        lTmp := IsTruthy(lVarValue);
//      end
//      else
//      begin
//        lTmp := lList.Count > 0;
//      end;
//
//      if lNegation then
//      begin
//        Exit(not lTmp);
//      end;
//      Exit(lTmp);
//    end
//    else if [viObject, viJSONObject] * lVariable.VarOption <> [] then
//    begin
//      if lHasMember then
//      begin
//        if lVarMembers.StartsWith('@@') then
//        begin
//          lVarValue := GetPseudoVariable(lCurrentIterator.IteratorPosition, lVarMembers);
//        end
//        else
//        begin
//          lVarValue := GetVarAsTValue(lDataSourceName);
//        end;
//        lTmp := IsTruthy(lVarValue);
//      end
//      else
//      begin
//        lTmp := not lVarValue.IsEmpty;
//      end;
//      if lNegation then
//      begin
//        Exit(not lTmp);
//      end;
//      Exit(lTmp);
//    end
//    else if viSimpleType in lVariable.VarOption then
//    begin
//      lTmp := IsTruthy(lVariable.VarValue);
//      Exit(lNegation xor lTmp)
//    end;
//  end
//  else
//  begin
//    lHandled := False;
//    DoOnGetValue(lVarName, lVarMembers, lVarValue, lHandled);
//    if lHandled then
//    begin
//      lTmp := IsTruthy(lVarValue);
//      if lNegation then
//      begin
//        Exit(not lTmp);
//      end;
//      Exit(lTmp);
//    end;
//  end;
//  Exit(lNegation xor False);
//end;

function TTProCompiledTemplate.EvaluateIfExpressionAt(var Idx: UInt64): Boolean;
var
  lMustBeEncoded: Boolean;
begin
  Inc(Idx);
  if fTokens[Idx].TokenType <> ttBoolExpression then
  begin
    Error('Expected ttBoolExpression after ttIfThen');
  end;
  Result := IsTruthy(EvaluateValue(Idx, lMustBeEncoded));
end;

function TTProCompiledTemplate.EvaluateValue(var Idx: UInt64; out MustBeEncoded: Boolean): TValue;
var
  lCurrTokenType: TTokenType;
  lVarName: string;
  lFilterName: string;
  lFilterParCount: Int64;
  lFilterParameters: TArray<String>;
  I: Integer;
  lNegated: Boolean;
begin
  // Ref1 contains the optional filter parameter number (-1 if there isn't any filter)
  // Ref2 is -1 if the variable must be HTMLEncoded, while contains 1 is the value must not be HTMLEncoded
  MustBeEncoded := fTokens[Idx].Ref2 = -1;
  lCurrTokenType := fTokens[Idx].TokenType;
  lVarName := fTokens[Idx].Value1;
  lNegated := lVarName.StartsWith('!');
  if lNegated then
  begin
    lVarName := lVarName.Substring(1);
  end;

  if fTokens[Idx].Ref1 > -1 {has a filter with Ref1 parameters cout} then
  begin
    Inc(Idx);
    lFilterName := fTokens[Idx].Value1;
    lFilterParCount := fTokens[Idx].Ref1;  // parameter count
    SetLength(lFilterParameters, lFilterParCount);
    for I := 0 to lFilterParCount - 1 do
    begin
      Inc(Idx);
      Assert(fTokens[Idx].TokenType = ttFilterParameter);
      lFilterParameters[I] := fTokens[Idx].Value1;
    end;
    case lCurrTokenType of
      ttValue: Result := ExecuteFilter(lFilterName, lFilterParameters, GetVarAsTValue(lVarName));
      ttBoolExpression: Result := IsTruthy(ExecuteFilter(lFilterName, lFilterParameters, GetVarAsTValue(lVarName)));
      ttLiteralString: Result := ExecuteFilter(lFilterName, lFilterParameters, lVarName);
      else
        Error('Invalid token in EvaluateValue');
    end;
  end
  else
  begin
    case lCurrTokenType of
      ttValue: Result := GetVarAsString(lVarName);
      ttBoolExpression: Result := IsTruthy(GetVarAsTValue(lVarName));
      ttLiteralString: Result := lVarName;
      else
        Error('Invalid token in EvaluateValue');
    end;
  end;
  if lNegated then
  begin
    Result := not Result.AsBoolean;
  end;
end;

procedure TTProCompiledTemplate.SaveToFile(const FileName: String);
var
  lToken: TToken;
  lBW: TBinaryWriter;
begin
  lBW := TBinaryWriter.Create(TFileStream.Create(FileName, fmCreate or fmOpenWrite or fmShareDenyNone), nil, True);
  try
    for lToken in fTokens do
    begin
      lToken.SaveToBytes(lBW);
    end;
  finally
    lBW.Free;
  end;
end;

procedure TTProCompiledTemplate.SetData(const Name: String; Value: TValue);
var
  lWrappedList: ITProWrappedList;
begin
  if Value.IsEmpty then
  begin
    GetVariables.Add(Name, nil);
    Exit;
  end;

  case Value.Kind of
    tkClass:
    begin
      if Value.AsObject is TDataSet then
      begin
        GetVariables.Add(Name, TVarDataSource.Create(Value.AsObject, [viDataSet, viIterable]));
      end
      else
      if Value.AsObject is TJDOJsonObject then
      begin
        GetVariables.Add(Name, TVarDataSource.Create(TJDOJsonObject(Value.AsObject), [viJSONObject]));
      end
      else
      if Value.AsObject is TJDOJsonArray then
      begin
        raise ETProRenderException.Create('JSONArray cannot be used directly [HINT] Define a JSONObject variable with a JSONArray property');
      end
      else
      begin
        if TTProDuckTypedList.CanBeWrappedAsList(Value.AsObject, lWrappedList) then
        begin
          GetVariables.Add(Name, TVarDataSource.Create(TTProDuckTypedList(Value.AsObject), [viListOfObject, viIterable]));
        end
        else
        begin
          GetVariables.Add(Name, TVarDataSource.Create(Value.AsObject, [viObject]));
        end;
      end;
    end;
    tkInteger, tkString, tkUString, tkFloat, tkEnumeration : GetVariables.Add(Name, TVarDataSource.Create(Value, [viSimpleType]));
    else
      raise ETProException.Create('Invalid type for variable "' + Name + '": ' + TRttiEnumerationType.GetName<TTypeKind>(Value.Kind));
  end;

end;


procedure TTProCompiledTemplate.SetOnGetValue(
  const Value: TTProCompiledTemplateGetValueEvent);
begin
  fOnGetValue := Value;
end;

procedure TTProCompiledTemplate.SplitVariableName(
  const VariableWithMember: String; out VarName, VarMembers: String);
var
  lDotPos: Integer;
begin
  VarName := VariableWithMember;
  VarMembers := '';
  lDotPos := VarName.IndexOf('.');
  if lDotPos > -1 then
  begin
    VarName := VariableWithMember.Substring(0, lDotPos);
    VarMembers := VariableWithMember.Substring(lDotPos + 1);
  end;
end;

function TTProCompiledTemplate.WalkThroughLoopStack(const VarName: String;
  out BaseVarName, FullPath: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := fLoopsStack.Count - 1 downto 0 do
  begin
    if VarName = fLoopsStack[I].IteratorName then
    begin
      BaseVarName := fLoopsStack[I].DataSourceName;
      FullPath := fLoopsStack[I].FullPath + '[' + fLoopsStack[I].IteratorPosition.ToString + ']';
      Result := True;
    end;
  end;
end;

procedure TTProCompiledTemplate.ClearData;
begin
  GetVariables.Clear;
end;

{ TVarInfo }

constructor TVarDataSource.Create(const VarValue: TValue;
  const VarOption: TTProVariablesInfos);
begin
  Self.VarValue := VarValue;
  Self.VarOption := VarOption;
end;

{ TTProVariables }

constructor TTProVariables.Create;
begin
  inherited Create([doOwnsValues]);
end;


//////////////////////
/// UTILS

class function TTProRTTIUtils.GetProperty(AObject: TObject; const APropertyName: string): TValue;
var
  Prop: TRttiProperty;
  ARttiType: TRttiType;
begin
  ARttiType := GlContext.GetType(AObject.ClassType);
  if not Assigned(ARttiType) then
    raise Exception.CreateFmt('Cannot get RTTI for type [%s]', [ARttiType.ToString]);
  Prop := ARttiType.GetProperty(APropertyName);
  if not Assigned(Prop) then
    raise Exception.CreateFmt('Cannot get RTTI for property [%s.%s]', [ARttiType.ToString, APropertyName]);
  if Prop.IsReadable then
    Result := Prop.GetValue(AObject)
  else
    raise Exception.CreateFmt('Property is not readable [%s.%s]', [ARttiType.ToString, APropertyName]);
end;

{ TDuckTypedList }

procedure TTProDuckTypedList.Add(const AObject: TObject);
begin
  if not Assigned(FAddMethod) then
    raise ETProDuckTypingException.Create('Cannot find method "Add" in the Duck Object.');
  FAddMethod.Invoke(FObjectAsDuck, [AObject]);
end;

class function TTProDuckTypedList.CanBeWrappedAsList(const AInterfaceAsDuck: IInterface): Boolean;
begin
  Result := CanBeWrappedAsList(TObject(AInterfaceAsDuck));
end;

class function TTProDuckTypedList.CanBeWrappedAsList(const AObjectAsDuck: TObject): Boolean;
var
  lList: ITProWrappedList;
begin
  Result := CanBeWrappedAsList(AObjectAsDuck, lList);
end;

class function TTProDuckTypedList.CanBeWrappedAsList(const AObjectAsDuck: TObject; out AMVCList: ITProWrappedList): Boolean;
var
  List: ITProWrappedList;
begin
  List := TTProDuckTypedList.Create(AObjectAsDuck);
  Result := List.IsWrappedList;
  if Result then
    AMVCList := List;
end;

procedure TTProDuckTypedList.Clear;
begin
  if not Assigned(FClearMethod) then
    raise ETProDuckTypingException.Create('Cannot find method "Clear" in the Duck Object.');
  FClearMethod.Invoke(FObjectAsDuck, []);
end;

function TTProDuckTypedList.Count: Integer;
begin
  Result := 0;

  if (not Assigned(FGetCountMethod)) and (not Assigned(FCountProperty)) then
    raise ETProDuckTypingException.Create('Cannot find property/method "Count" in the Duck Object.');

  if Assigned(FCountProperty) then
    Result := FCountProperty.GetValue(FObjectAsDuck).AsInteger
  else if Assigned(FGetCountMethod) then
    Result := FGetCountMethod.Invoke(FObjectAsDuck, []).AsInteger;
end;

constructor TTProDuckTypedList.Create(const AInterfaceAsDuck: IInterface);
begin
  Create(TObject(AInterfaceAsDuck));
end;

constructor TTProDuckTypedList.Create(const AObjectAsDuck: TObject);
begin
  inherited Create;
  FObjectAsDuck := AObjectAsDuck;

  if not Assigned(FObjectAsDuck) then
    raise ETProDuckTypingException.Create('Duck Object can not be null.');

  FObjType := GlContext.GetType(FObjectAsDuck.ClassInfo);

  FAddMethod := nil;
  FClearMethod := nil;
  FGetItemMethod := nil;
  FGetCountMethod := nil;
  FCountProperty := nil;

  if IsWrappedList then
  begin
    FAddMethod := FObjType.GetMethod('Add');
    FClearMethod := FObjType.GetMethod('Clear');

{$IF CompilerVersion >= 23}
    if Assigned(FObjType.GetIndexedProperty('Items')) then
      FGetItemMethod := FObjType.GetIndexedProperty('Items').ReadMethod;

{$IFEND}
    if not Assigned(FGetItemMethod) then
      FGetItemMethod := FObjType.GetMethod('GetItem');

    if not Assigned(FGetItemMethod) then
      FGetItemMethod := FObjType.GetMethod('GetElement');

    FGetCountMethod := nil;
    FCountProperty := FObjType.GetProperty('Count');
    if not Assigned(FCountProperty) then
      FGetCountMethod := FObjType.GetMethod('Count');
  end;
end;

function TTProDuckTypedList.GetItem(const AIndex: Integer): TObject;
var
  lValue: TValue;
begin
  if not Assigned(FGetItemMethod) then
    raise ETProDuckTypingException.Create
      ('Cannot find method Indexed property "Items" or method "GetItem" or method "GetElement" in the Duck Object.');
  GetItemAsTValue(AIndex, lValue);

  if lValue.Kind = tkInterface then
  begin
    Exit(TObject(lValue.AsInterface));
  end;
  if lValue.Kind = tkClass then
  begin
    Exit(lValue.AsObject);
  end;
  raise ETProDuckTypingException.Create('Items in list can be only objects or interfaces');
end;

procedure TTProDuckTypedList.GetItemAsTValue(const AIndex: Integer;
  out AValue: TValue);
begin
  AValue := FGetItemMethod.Invoke(FObjectAsDuck, [AIndex]);
end;

function TTProDuckTypedList.IsWrappedList: Boolean;
var
  ObjectType: TRttiType;
begin
  ObjectType := GlContext.GetType(FObjectAsDuck.ClassInfo);

  Result := (ObjectType.GetMethod('Add') <> nil) and (ObjectType.GetMethod('Clear') <> nil)

{$IF CompilerVersion >= 23}
    and (ObjectType.GetIndexedProperty('Items') <> nil) and (ObjectType.GetIndexedProperty('Items').ReadMethod <> nil)

{$IFEND}
    and (ObjectType.GetMethod('GetItem') <> nil) or (ObjectType.GetMethod('GetElement') <> nil) and
    (ObjectType.GetProperty('Count') <> nil);
end;

function TTProDuckTypedList.ItemIsObject(const AIndex: Integer; out AValue: TValue): Boolean;
begin
  GetItemAsTValue(AIndex, AValue);
  Result := AValue.IsObject;
end;

class function TTProDuckTypedList.Wrap(const AObjectAsDuck: TObject): ITProWrappedList;
var
  List: ITProWrappedList;
begin
  if AObjectAsDuck is TTProDuckTypedList then
    Exit(TTProDuckTypedList(AObjectAsDuck));
  Result := nil;
  List := TTProDuckTypedList.Create(AObjectAsDuck);
  if List.IsWrappedList then
    Result := List;
end;


{ TLoopStackItem }

constructor TLoopStackItem.Create(DataSourceName, LoopExpression,
  FullPath: String; IteratorName: String);
begin
  Self.DataSourceName := DataSourceName;
  Self.LoopExpression := LoopExpression;
  Self.FullPath := FullPath;
  Self.IteratorName := IteratorName;
  Self.IteratorPosition := -1;
end;

function TLoopStackItem.IncrementIteratorPosition: Integer;
begin
  Inc(IteratorPosition);
  Result := IteratorPosition;
end;

{ TTProConfiguration }

class procedure TTProConfiguration.RegisterHandlers(const TemplateProCompiledTemplate: ITProCompiledTemplate);
begin
  if Assigned(fOnContextConfiguration) then
  begin
    fOnContextConfiguration(TemplateProCompiledTemplate);
  end;
end;

initialization
GlContext := TRttiContext.Create;
JsonSerializationConfig.LineBreak := sLineBreak;

finalization
GlContext.Free;

end.
