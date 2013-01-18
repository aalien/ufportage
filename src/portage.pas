
(* Unit for easy communications with Emerge and Portage

   *** Functions ***
   Install: Installs the package(s) given in parameters. Use space separeted list for multiple packages.
   Update: Updates the given packages. Use space separeted list for multiple packages or "world" to update everything.
   UnInstall: Removes the packages. Again, space separeted list works for multiple packages.
   SearchFromPortage: Searches the package from Portage.
   GetPackageInfo: Returns the package info (name, size, version, homepage...) in a SearchResults record .
   GetInstalledPackages: Returns a TStringList with all the installed packages in Portage.
   ListFilesInPortage: Returns a list with all the packages in category given in parameter. If category is empty,
                       the list of all categorys in Portage will be returned.
   GetUseFlags: Fills two array with the use flags and the ccording descriptions.
   GetMirrors: Tries to find 3 mirrors for the use of make.conf. Requires mirrorselect tool.
   ReadConfig: Reads the make.conf config file. Results can be read from the Config variable.
   WriteConfig: Writes the configs given in parametre to the make.conf config file and refreshes the Config variable.

   *** Helper functions ***
   Explode: Explodes the string "text" at the characters given in parameters and writes the parts to an array.
   InArray: Returns true if the given string is in the array.
   MerkinNsIndex: Get the nth index of a character in a string.
   ParsePackageName: Returns package's name and version.
   Sort: Overrides TStringList's virtual sort function.
   GetTextBetween: Returns the text from the line between given characters.
   ParseEmergeOutput: Used internally. Parses the string given in parameters and tells what's happening in the InstallInfo variable.

   *** Variables ***
   InstallInfo: Record with information of what is being done while working with emerge.
   Config: Portages config. Update with ReadConfig.
   EmergeEvent: This event gets called every time there is something happening in the emerge process running.
   EmergePID: Process ID for currently running emerge process.

   Antti Laine
   <antti.a.laine@mbnet.fi> 
*)

unit Portage;

{$mode objfpc}{$H+}{$I-}

interface

uses
  BaseUnix, Unix, SysUtils, StrUtils, Classes, gtk2, gdk2, glib2;

type TEmergeFunc = (efInstall, efUninstall, efUpdate, efSync);

type TEmergeEventType = (eeCurrentMessage, eeOtherMessage, eePackage, eeError, eeSuccess, eeIdle);

type TEmergeEvent = procedure (change: TEmergeEventType);


type SearchResults = record
  Name: String;
  LatestVersion: String;
  InstalledVersion: String;
  DownloadSize: String;
  Homepage: String;
  Description: String;
  License: String;
end;

type EbuildInfo = record
  Category: String;
  Name: String;
  Version: String;
  Suffix: String;
  Rev: String;
end;

type InstallLog = record
  PackageName: String;
  CurrentMessage: String;
  OtherMessages: String;
  Packages: Integer;
  CurrentPackage: Integer;
end;

type PortageConfig = record
  PortageDir: String;
  PortageDirOverlay: String;
  DistfilesDir: String;
  GentooMirrors: String;
  SyncMirrors: String;
  BinaryMirrors: String;
  UseFlags: String;
  CFlags: String;
  AcceptKeywords: String;
end;

  procedure Emerge(package: String; func: TEmergeFunc);
  procedure StopEmerge;
  function SearchFromPortage(SearchString: String): TStringList;
  function GetPackageInfo(package: String): SearchResults;
  function GetInstalledPackages: TStringList;
  function ListFilesInPortage(category: String): TStringList;
  procedure GetUseFlags(var useflags: Array of String; var descriptions: Array of String);
  function GetMirrors: String;
  procedure ReadConfig;
  procedure WriteConfig(config: PortageConfig);
  procedure Explode(text: String; character: String; var table: Array of String);
  function InArray(line: String; table: Array of String): Boolean;
  procedure ParsePackageName(package: String; var packagename: String; var version: String);
  procedure Sort(var list: TStrings);
  function GetTextBetween(line: String; start: char; finish: char): String;
  procedure ParseEmergeOutput(rivi: String);

const
  PortageConfigFile: String = '/etc/make.conf';
  PortageGlobalsFile: String = '/etc/make.globals';
var
  InstallInfo: InstallLog;
  Config: PortageConfig;
  EmergeEvent: TEmergeEvent;
  EmergePID: Longint;

implementation

//call emerge with the wanted action
//FIXME: pending events are not handled when portage is downloading a file
//TODO: add a possibility to resume after error when updating
procedure Emerge(package: String; func: TEmergeFunc);
const
  nocolors: String = 'NOCOLOR="TRUE" ';
var
  fpi, fpo, fpe: Text;
  Buffer: String;
  closestatus: Longint;
begin
  InstallInfo.CurrentPackage := 0;
  InstallInfo.Packages := 0;
  InstallInfo.PackageName := package;
  InstallInfo.CurrentMessage := '';
  InstallInfo.OtherMessages := '';
  case func of
    efinstall: EmergePID := AssignStream(fpi, fpo, fpe, nocolors + '/usr/bin/emerge ' + package, []); //open a pipe to emerge program, ask to install a package and listen
    efUninstall: EmergePID := AssignStream(fpi, fpo, fpe, nocolors + '/usr/bin/emerge -C ' + package, []); //ask emerge to remove a package
    efUpdate: EmergePID := AssignStream(fpi, fpo, fpe, nocolors + '/usr/bin/emerge -u ' + package, []); //update
    efSync: EmergePID := AssignStream(fpi, fpo, fpe, nocolors + '/usr/bin/emerge sync', []); //sync
  end;
  while not (EoF(fpi) and EoF(fpe)) do begin //read from the pipe until it closes
    if SelectText(fpi, 250) > 0 then begin //wait for something to be read from the pipe, and carry on if nothing comes up
      ReadLn(fpi, Buffer); //read line-by-line
      ParseEmergeOutput(Buffer); //parse output
    end;
    if SelectText(fpe, 250) > 0 then begin //same thing for stderror pipe
      ReadLn(fpe, Buffer);
      ParseEmergeOutput(Buffer);
    end;
    EmergeEvent(eeIdle); //send an idle event to notify we're still alive
  end;
  closestatus := PClose(fpi); //close the pipes
  Close(fpo);
  Close(fpe);
  if closestatus = 0 then EmergeEvent(eeSuccess)
  else EmergeEvent(eeError);
end;

//kills the emerge process
procedure StopEmerge;
begin
  FpKill(EmergePID, SIGINT);
end;

//search the program given as parameter from portage
//and return a list of found packages and their descriptions
function SearchFromPortage(SearchString: String): TStringList;
var
  results, tmp, tmp2: TStringList;
  i, j: Integer;
begin
  results := TStringList.Create;
  results.Clear;
  tmp := TStringList.Create; //temporary variable for the list which has all the categories
  tmp2 := TStringList.Create; //temporary variable for the list which has all the packages in a category
  tmp := ListFilesInPortage(''); //get the categories and put them in a list
  for i := 0 to tmp.Count - 1 do begin //go trough the categories
    tmp2 := ListFilesInPortage(tmp.Strings[i]); //get the packages in the category and put them in a list
    for j := 0 to tmp2.Count - 1 do begin //go trough the packages
      if AnsiContainsStr(tmp2.Strings[j], SearchString) then begin //compare the packages name with the given parameter
				results.Add(tmp.Strings[i] + '/' + tmp2.Strings[j]); //if it was the same, add to the list of results
      end;
    end;
  end;
  Result := results;
end;

//Returs the information about the wanted package in a parsed form
function GetPackageInfo(package: String): SearchResults;

  //get the latest version of wanted package
  function GetLatestVersion(package_: String): String;
  var
    fp: Text;
    Buffer: String;
  begin
    Result := '';
    POpen(fp, '/usr/lib/portage/bin/portageq best_visible / ' + package_, 'r'); //ask for the best unmasked version of the package
    while not EoF(fp) do begin //read from the pipe
      ReadLn(fp, buffer);
      if buffer <> '' then
	Result := buffer;
    end;
    PClose(fp);
    if Result <> '' then Exit
    else begin //masked
      Result := 'masked';
    end;
  end;

  //get the installed version of package
  function GetInstalledVersion(package_: String): String;
  var
    InstalledPackages: TStringList;
    i: Integer;
    name, name_, version, version_: String;
  begin
    Result := '';
    ParsePackageName(package_, name_, version_);
    InstalledPackages := TStringList.Create;
    InstalledPackages := GetInstalledPackages;
    Sort(InstalledPackages);
    for i := InstalledPackages.Count - 1 downto 0 do begin
      ParsePackageName(InstalledPackages.Strings[i], name, version);
      if name = name_ then
	Result := InstalledPackages[i];
    end;
  end;

var
  packagesearched: String;
  installedversion: String;
  category, name, version, versioninstalled: String;
  ebuildfile, digestfile: String;
  buffer: String;
  packageinfo: Text;
  results: SearchResults;
  table: array[0..3] of String;
  size: Integer;
begin
  packagesearched := GetLatestVersion(package);
  if packagesearched = 'masked' then begin //package is masked
    results.LatestVersion := '[ Masked ]';
    Result := results;
    Exit;
  end;
  ParsePackageName(packagesearched, name, version);
  category := Copy(packagesearched, 1, Pos('/', packagesearched) - 1);
  results.Name := category + '/' + name;
  results.LatestVersion := version;
  installedversion := GetInstalledVersion(package);
  if installedversion = '' then
    results.InstalledVersion := '[ Not Installed ]'
  else begin
    ParsePackageName(installedversion, name, versioninstalled);
    results.InstalledVersion := versioninstalled;
  end;
  ebuildfile := Config.PortageDir + '/' + category + '/' + name + '/' + name + '-' + version + '.ebuild';
  if FileExists(ebuildfile) then begin
    Assign(packageinfo, ebuildfile);
    Reset(packageinfo);
    while not EoF(packageinfo) do begin
      ReadLn(packageinfo, buffer);
      if AnsiStartsStr('HOMEPAGE', buffer) then
				results.Homepage := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
			if AnsiStartsStr('DESCRIPTION', buffer) then
				results.Description := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
      if AnsiStartsStr('LICENSE', buffer) then
				results.License := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
    end;
    Close(packageinfo);
  end;
  digestfile := Config.PortageDir + '/' + category + '/' + name + '/files/digest-' + name + '-' + version;
  Size := 0;
  if FileExists(digestfile) then begin
    Assign(packageinfo, digestfile);
    Reset(packageinfo);
    while not EoF(packageinfo) do begin
      ReadLn(packageinfo, buffer);
      if buffer <> '' then begin
				Explode(buffer, ' ', table);
				try
				 Size := Size + StrToInt(table[3]);
				except
				 on EConvertError do
				 Continue;
				end;
      end;
    end;
  end;
  if Size <> 0 then begin
    results.DownloadSize := IntToStr(Size div 1024) + ' kB';
  end
  else begin
    results.DownloadSize := '[empty/missing/bad digest]';
  end;
  Result := results;
end;

//search the portage for installed packages and return the in a list
function GetInstalledPackages: TStringList;
const
  PortageInstalledDir: String = '/var/db/pkg/';
var
  Info: TSearchRec;
  taulukko: array [0..5] of String;
  tmp, tmp2: TStringList;
  i: Integer;
begin
  tmp := TStringList.Create;
  tmp2 := TStringList.Create;
  if FindFirst(PortageInstalledDir + '*', faAnyFile, Info) = 0 then begin
    repeat
      if (((Info.Attr and faDirectory) = faDirectory) and not ((Info.Name = '.') or (Info.Name = '..'))) then begin
				tmp.Add(Info.Name);
      end;
    until FindNext(Info) <> 0;
    FindClose(Info);
  end;
  for i := 0 to tmp.Count - 1 do begin
    if FindFirst(PortageInstalledDir + tmp.Strings[i] + '/*', faAnyFile, Info) = 0 then begin
      repeat
				if (((Info.Attr and faDirectory) = faDirectory) and not ((Info.Name = '.') or (Info.Name = '..'))) then begin
					Explode(PortageInstalledDir + tmp.Strings[i] + '/' + Info.Name, '/', taulukko);
					tmp2.Add(taulukko[4] + '/' + taulukko[5]);
				end;
      until FindNext(Info) <> 0;
    end;
    FindClose(Info);
  end;
  Result := tmp2;
end;

//find files in portage which belong to the given category
//if category is empty, return all the categories in portage
function ListFilesInPortage(category: String): TStringList;
var
  Info : TSearchRec;
  tmp: TStringList;
begin
  tmp := TStringList.Create;
  if FindFirst (Config.PortageDir + '/' + category + '/*', faAnyFile, Info) = 0 then begin
    repeat
      begin
        if (((Info.Attr and faDirectory) = faDirectory) and not ((Info.Name = '.') or (Info.Name = '..'))) then begin
					if (not (category = '') or (AnsiContainsStr(Info.Name, '-'))) then tmp.Add(Info.Name);
				end;
      end;
    until FindNext(info) <> 0;
  end;
  FindClose(Info);
  Result := tmp;
end;

procedure GetUseFlags(var useflags: Array of String; var descriptions: Array of String);
var
  useflagsfilepath: String;
  useflagsfile: Text;
  buffer: String;
  table: Array [0..1] of String;
  i: Integer;
begin
  i := 0;
  useflagsfilepath := Config.PortageDir + '/profiles/use.desc';
  if FileExists(useflagsfilepath) then begin
    Assign(useflagsfile, useflagsfilepath);
    Reset(useflagsfile);
    while not EoF(useflagsfile) do begin
      ReadLn(useflagsfile, buffer);
      //we shouldn't read the line in these cases
      if buffer = '' then //line is empty
				Continue;
      if buffer[1] = '#' then begin //line is a comment
				if AnsiContainsStr(buffer, '# The following flags are NOT to be set or unset by users') then //end of use-flags
					Break
				else
				 Continue;
      end;
      if AnsiContainsStr(buffer, '!!internal use only!!') then //these flags are not allowed to be set by user
				Continue;

      Explode(buffer, ' - ', table);
      useflags[i] := table[0];
      descriptions[i] := table[1];
      Inc(i);
    end;
  end;
end;

//This function uses the mirrorselect program! app-portage/mirrorselect
//tries to find the three best mirrors
function GetMirrors: String;
var
  fp: Text;
  Buffer: String;
  status: Integer;
begin
  POpen(fp, 'mirrorselect -a -s3 -o' , 'r'); //ask mirrorselect to find three best mirrors
  while not EoF(fp) do begin //luetaan
    while gtk_events_pending() = 1 do begin //let gtk's main loop handle the pending events
      gtk_main_iteration();
    end;
    if SelectText(fp, 500) > 0 then begin
      ReadLn(fp, Buffer); //read line-by-line
    end
    else Continue;
    if AnsiContainsStr(Buffer, 'GENTOO_MIRRORS') then
      Result := Copy(Buffer, 17, Length(Buffer) - 17);
  end;
  status := PClose(fp);
  if status <> 0 then
    Result := 'Error (' + IntToStr(status) + ')';
end;

//read portage's config files and return configs in a parsed form
procedure ReadConfig;
var
  configfile: Text;
  buffer: String;
begin
  //get globals
  Assign(configfile, PortageGlobalsFile);
  Reset(configfile);
  while not EoF(configfile) do begin
    ReadLn(configfile, buffer);
    if AnsiStartsStr('GENTOO_MIRRORS=', buffer) then
      Config.GentooMirrors := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
    if AnsiStartsStr('SYNC=', buffer) then
      Config.SyncMirrors := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
    if AnsiStartsStr('PORTDIR=', buffer) then
      Config.PortageDir := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
    if AnsiStartsStr('CFLAGS=', buffer) then
      Config.CFlags := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
  end;
  Close(configfile);
  //override with user's settings
  Assign(configfile, PortageConfigFile);
  Reset(configfile);
  while not EoF(configfile) do begin
    ReadLn(configfile, buffer);
    if AnsiStartsStr('GENTOO_MIRRORS=', buffer) then
      Config.GentooMirrors := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
    if AnsiStartsStr('SYNC=', buffer) then
      Config.SyncMirrors := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
    if AnsiStartsStr('PORTDIR=', buffer) then
      Config.PortageDir := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
    if AnsiStartsStr('PORTDIR_OVERLAY=', buffer) then
      Config.PortageDirOverlay := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
    if AnsiStartsStr('DISTDIR=', buffer) then
      Config.DistfilesDir := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
    if AnsiStartsStr('CFLAGS=', buffer) then
      Config.CFlags := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
    if AnsiStartsStr('USE=', buffer) then
      Config.UseFlags := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
    if AnsiStartsStr('ACCEPT_KEYWORDS=', buffer) then
      Config.AcceptKeywords := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
    if AnsiStartsStr('PORTAGE_BINHOST=', buffer) then
      Config.BinaryMirrors := DelChars(Copy(buffer, Pos('=', buffer) + 1, Length(buffer)), '"');
   end;
  Close(configfile);
end;

//write given configs to portage's config files
procedure WriteConfig(config: PortageConfig);
var
  configfile: TStringList;
  i: Integer;
begin
  configfile := TStringList.Create;
  configfile.LoadFromFile(PortageConfigFile);
  for i := 0 to configfile.Count - 1 do begin //if config is specified or commented out, and our config is not empty, update
    if ((Copy(configfile.Strings[i], 1, Length('GENTOO_MIRRORS=')) = 'GENTOO_MIRRORS=') or (Copy(configfile.Strings[i], 1, Length('#GENTOO_MIRRORS=')) = '#GENTOO_MIRRORS=')) and (config.GentooMirrors <> '') then begin
      configfile.Strings[i] := 'GENTOO_MIRRORS="' + config.GentooMirrors + '"';
      config.GentooMirrors := '';
    end;
    if ((Copy(configfile.Strings[i], 1, Length('SYNC=')) = 'SYNC=') or (Copy(configfile.Strings[i], 1, Length('#SYNC=')) = '#SYNC=')) and (config.SyncMirrors <> '') then begin
      configfile.Strings[i] := 'SYNC="' + config.SyncMirrors + '"';
      config.SyncMirrors := '';
    end;
    if ((Copy(configfile.Strings[i], 1, Length('PORTDIR=')) = 'PORTDIR=') or (Copy(configfile.Strings[i], 1, Length('#PORTDIR=')) = '#PORTDIR=')) and (config.PortageDir <> '') then begin
      configfile.Strings[i] := 'PORTDIR="' + config.PortageDir + '"';
      config.PortageDir := '';
    end;
    if ((Copy(configfile.Strings[i], 1, Length('PORTDIR_OVERLAY=')) = 'PORTDIR_OVERLAY=') or (Copy(configfile.Strings[i], 1, Length('#PORTDIR_OVERLAY=')) = '#PORTDIR_OVERLAY=')) and (config.PortageDirOverlay <> '') then begin
      configfile.Strings[i] := 'PORTDIR_OVERLAY="' + config.PortageDirOverlay + '"';
      config.PortageDirOverlay := '';
    end;
    if ((Copy(configfile.Strings[i], 1, Length('DISTDIR=')) = 'DISTDIR=') or (Copy(configfile.Strings[i], 1, Length('#DISTDIR=')) = '#DISTDIR=')) and (config.DistfilesDir <> '') then begin
      configfile.Strings[i] := 'DISTDIR="' + config.DistfilesDir + '"';
      config.DistfilesDir := '';
    end;
    if ((Copy(configfile.Strings[i], 1, Length('CFLAGS=')) = 'CFLAGS=') or (Copy(configfile.Strings[i], 1, Length('#CFLAGS=')) = '#CFLAGS=')) and (config.CFlags <> '') then begin
      configfile.Strings[i] := 'CFLAGS="' + config.CFlags + '"';
      config.CFlags := '';
    end;
    if ((Copy(configfile.Strings[i], 1, Length('USE=')) = 'USE=') or (Copy(configfile.Strings[i], 1, Length('#USE=')) = '#USE=')) and (config.UseFlags <> '') then begin
      configfile.Strings[i] := 'USE="' + config.UseFlags + '"';
      config.UseFlags := '';
    end;
    if ((Copy(configfile.Strings[i], 1, Length('ACCEPT_KEYWORDS=')) = 'ACCEPT_KEYWORDS=') or (Copy(configfile.Strings[i], 1, Length('#ACCEPT_KEYWORDS=')) = '#ACCEPT_KEYWORDS=')) and (config.AcceptKeywords <> '') then begin
      configfile.Strings[i] := 'ACCEPT_KEYWORDS="' + config.AcceptKeywords + '"';
      config.AcceptKeywords := '';
    end;
    if ((Copy(configfile.Strings[i], 1, Length('PORTAGE_BINHOST=')) = 'PORTAGE_BINHOST=') or (Copy(configfile.Strings[i], 1, Length('#PORTAGE_BINHOST=')) = '#PORTAGE_BINHOST=')) and (config.BinaryMirrors <> '') then begin
      configfile.Strings[i] := 'PORTAGE_BINHOST="' + config.BinaryMirrors + '"';
      config.BinaryMirrors := '';
    end;
  end;

  //if some configs were not updated, write new ones to the end of the file
  //TODO: We could add some comments for these
  if config.GentooMirrors <> '' then configfile.Add('GENTOO_MIRRORS="' + config.GentooMirrors + '"');
  if config.SyncMirrors <> '' then configfile.Add('SYNC="' + config.SyncMirrors + '"');
  if config.PortageDir <> '' then configfile.Add('PORTDIR="' + config.PortageDir + '"');
  if config.PortageDirOverlay <> '' then configfile.Add('PORTDIR_OVERLAY="' + config.PortageDirOverlay + '"');
  if config.DistfilesDir <> '' then configfile.Add('DISTDIR="' + config.DistfilesDir + '"');
  if config.CFlags <> '' then configfile.Add('CFLAGS="' + config.CFlags + '"');
  if config.UseFlags <> '' then configfile.Add('USE="' + config.UseFlags + '"');
  if config.AcceptKeywords <> '' then configfile.Add('ACCEPT_KEYWORDS="' + config.AcceptKeywords + '"');
  if config.BinaryMirrors <> '' then configfile.Add('PORTAGE_BINHOST="' + config.BinaryMirrors + '"');

  try
    configfile.SaveToFile(PortageConfigFile);
  except
    Exit;
  end;
end;


function InArray(line: String; table: Array of String): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := Low(table) to High(table) do begin
    if table[i] = line then begin
      Result := True;
      Break;
    end;
  end;
end;

procedure Explode(text: String; character: String; var table: Array of String);
var
  x: Integer;
begin
	x := 0;
	while AnsiContainsStr(text, character) do
	 begin
		if x = High(table) then Break;
		table[x] := Copy(text, 0, Pos(character, text) - 1);
		text := Copy(text, Pos(character, text) + 1, Length(text));
		x := x + 1;
		end;
	table[x] := text;
end;

procedure ParsePackageName(package: String; var packagename: String; var version: String);
var
  lastseparator: Integer;
  x, i: Integer;
begin
  x := 1;
  if package = '' then begin //no package. we have been had :o
    packagename := '';
    version := '';
    Exit;
  end;
  if Pos('/', package) > 0 then begin
    package := Copy(package, Pos('/', package) + 1, Length(package) - Pos('/', package));
  end;
  for i := 1 to Length(package) do begin
    if (package[i] = '-') and (package[i + 1] in ['0'..'9']) then Break //has a version number
    else if i = Length(package) then begin //no version number :( leave
      packagename := package;
      Exit;
    end;
  end;
  repeat
    lastseparator := NPos(package, '-', x);
    Inc(x);
  until (package[lastseparator + 1] in ['0'..'9']);
  packagename := Copy(package, 1, lastseparator - 1);
  version := Copy(package, lastseparator + 1, Length(package));
end;

//simple selection sort algorithm
procedure Sort(var list: TStrings);
var
  i, j:integer;
begin
  for i := 0 to list.Count - 1 do begin
    for j  := i + 1 to list.Count - 1 do begin
      if LowerCase(list[j]) < LowerCase(list[i]) then begin
        list.Exchange(j, i);
     end;
    end;
  end;
end;

function GetTextBetween(line: String; start: char; finish: char): String;
var
  startindex, endindex: Integer;
begin
  startindex := Pos(start, line);
  if finish <> start then endindex := Pos(finish, line)
  else endindex := NPos(line, finish, 2);
  Result := Copy(line, startindex + 1, endindex - startindex - 1);
end;

procedure ParseEmergeOutput(rivi: String);
begin
  if Copy(rivi, 1, 4) = '>>> /' then begin //file is being copied
    //">>> /path/to/file"
    InstallInfo.CurrentMessage := 'Copying file ' + Copy(rivi, 5, Length(rivi));
    EmergeEvent(eeCurrentMessage);
    Exit;
  end;

  if Copy(rivi, 1, 16) = '<<<        obj /' then begin //file is being removed
    //"<<<        obj /path/to/file"
    InstallInfo.CurrentMessage := 'Removing file ' + Copy(rivi, 16, Length(rivi));
    EmergeEvent(eeCurrentMessage);
    Exit;
  end;

  if Copy(rivi, 1, 10) = '>>> emerge' then begin //number of packages and the number of the current package
    //">>> emerge (%1 of %2) category/package"
    InstallInfo.CurrentPackage := StrToInt(Copy(rivi, Pos('>>> emerge (', rivi) + 12, Pos(' of', rivi) - Pos('>>> emerge (', rivi) - 12));
    InstallInfo.Packages := StrToInt(Copy(rivi, Pos('of ', rivi) + 3, Pos(')', rivi) - Pos('of ', rivi) - 3));
    InstallInfo.PackageName := Copy(rivi, Pos(')', rivi) + 2, Pos(' to', rivi) - Pos(')', rivi) - 2);
    EmergeEvent(eePackage);
    Exit;
  end;

  if Copy(rivi, 1, 3) = '>>>' then begin //a regular message
    //">>> message"
    InstallInfo.CurrentMessage := Copy(rivi, 5, Length(rivi));
    EmergeEvent(eeCurrentMessage);
    Exit;
  end;

  if Copy(rivi, 2, 1) = '*' then begin
    //"* another message"
    InstallInfo.OtherMessages := Copy(rivi, 3, Length(rivi));
    EmergeEvent(eeOtherMessage);
    Exit;
  end;

  if Copy(rivi, 1, 3) = '!!!' then begin
    //!!! ERROR:
    InstallInfo.OtherMessages := rivi;
    EmergeEvent(eeError);
  end;
end;

end.
