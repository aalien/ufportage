program ufportage;

{$MODE objfpc} {$H+} {$I-}
{$DEFINE GTK2_6}

uses cmem, baseunix, unix, unixutil, gtk2, gdk2, glib2, libglade2, classes, sysutils, portage;

var
  //glade's xml file
  xml: pGladeXML;
  //columns and renderers for lists
  renderer: pGtkCellRenderer;
  column: pGtkTreeViewColumn;
  selectionCategorys: pGtkTreeSelection;
  selectionPackages1: pGtkTreeSelection;
  selectionInstalledPackages1: pGtkTreeSelection;
  selectionPackages2: pGtkTreeSelection;
  selectionUseFlags: pGtkTreeSelection;
  //widgets
  //main window
  Form1: pGtkWidget;
    //dialog
    Dialog: pGtkWidget;
    //buttons
    ButtonInstall1: pGtkWidget;
    ButtonSync: pGtkWidget;
    ButtonInstallFromEbuild: pGtkWidget;
    ButtonUpdateList1: pGtkWidget;
    ButtonUninstall: pGtkWidget;
    ButtonUpdateWorld: pGtkWidget;
    ButtonUpdate: pGtkWidget;
    ButtonSearch: pGtkWidget;
    ButtonInstall2: pGtkWidget;
    ButtonFecthMirrors: pGtkWidget;
    ButtonResetSettings: pGtkWidget;
    ButtonApplySettings: pGtkWidget;
    ButtonEmptyDistfilesDirectory: pGtkWidget;
    //lists
    ListCategorys: pGtkWidget;
    ListPackages1: pGtkWidget;
    ListInstalledPackages1: pGtkWidget;
    ListPackages2: pGtkWidget;
    ListUseFlags: pGtkWidget;
    //labels
    LabelName1: pGtkWidget;
    LabelLatest1: pGtkWidget;
    LabelInstalled1: pGtkWidget;
    LabelHomepage1: pGtkWidget;
    LabelDescription1: pGtkWidget;
    LabelName2: pGtkWidget;
    LabelLatest2: pGtkWidget;
    LabelInstalled2: pGtkWidget;
    LabelHomepage2: pGtkWidget;
    LabelDescription2: pGtkWidget;
    //edits
    EditSearch: pGtkWidget;
    EditPortageMirrors: pGtkWidget;
    EditRSYNCMirrors: pGtkWidget;
    EditAcceptedKeywords: pGtkWidget;
    EditOptimizations: pGtkWidget;
    EditPortageDir: pGtkWidget;
    EditPortageOverlayDir: pGtkWidget;
    EditDistfilesDir: pGtkWidget;
    EditBinaryMirrors: pGtkWidget;
    //text view
    TextViewOutput: pGtkWidget;
    //text view's buffer
    TextViewBuffer: pGtkTextBuffer;
    //pages
    Pages: pGtkWidget;
  //Install window
  Form2: pGtkWidget;
    //label
    LabelInstallInfo: pGtkWidget;
    //buttons
    ButtonInstallFinished: pGtkWidget;
    ButtonInstallCancel: pGtkWidget;
    //progressbars
    Progressbar: pGtkWidget;
    ProgressbarStep: pGtkWidget;
  //Install from ebuild window
  Form3: pGtkWidget;
    //buttons
    ButtonEbuildOK: pGtkWidget;
    ButtonEbuildCancel: pGtkWidget;
    ButtonSelectEbuild: pGtkWidget;
    //edits
    EditEbuild: pGtkWidget;
    EditPortageCategorys: pGtkWidget;
    //combobox
    ComboPortageCategorys: pGtkWidget;
    //list of categorys in portage
    PortageCategorys: TStringList;

  //file selection dialog
  FileSelectionEbuild: pGtkWidget;
    //buttons
    ButtonSelectEbuildOK: pGtkWidget;
    ButtonSelectEbuildCancel: pGtkWidget;

//Takes a TStringList and returns an equal GtkTreeModel.
function StringListToGtkListStore(lista: TStrings): pGtkTreeModel;
var
  ListStore: pGtkListStore;
  ListIter: TGtkTreeIter;
  i: Integer;
begin
  ListStore := gtk_list_store_new(1, [G_TYPE_STRING]);
  for i := 0 to lista.Count - 1 do begin
    gtk_list_store_append(ListStore, @ListIter);
    gtk_list_store_set(ListStore, @ListIter, [0, PChar(Lista.Strings[i]), -1]);
    gtk_tree_sortable_set_sort_column_id(GTK_TREE_SORTABLE(ListStore), 0, GTK_SORT_ASCENDING);
  end;
  Result := GTK_TREE_MODEL(ListStore);
end;

//Populates the list of use flags
procedure PopulateListUseFlags;
var
  ListStore: pGtkListStore;
  ListIter: TGtkTreeIter;
  selecteduseflags: array[0..255] of String;
  useflags, descriptions: Array[0..255] of String;
  i: Integer;
begin
  Portage.ReadConfig;
  Portage.GetUseFlags(useflags, descriptions);
  ListStore := gtk_list_store_new(3, [G_TYPE_BOOLEAN, G_TYPE_STRING, G_TYPE_STRING]);
  Explode(Portage.Config.UseFlags, ' ', selecteduseflags);

  for i := 0 to High(useflags) do begin
    if useflags[i] = '' then Break; //lopetetaan tyhjaan riviin
    gtk_list_store_append(ListStore, @ListIter);
    gtk_list_store_set(ListStore, @ListIter, [1, pGChar(useflags[i]), 2, pGChar(descriptions[i]), -1]);
    if Portage.InArray(useflags[i], selecteduseflags) then begin
      gtk_list_store_set(ListStore, @ListIter, [0, True, -1]);
    end;
  end;
  gtk_tree_view_set_model(GTK_TREE_VIEW(ListUseFlags), GTK_TREE_MODEL(ListStore));
end;

procedure ToggleUseFlags(cell: pGtkCellRendererToggle; path_str: pgchar; data: gpointer);
var
  iter: TGtkTreeIter;
  model: pGtkTreeModel;
  path: pGtkTreePath;
  checked: gBoolean;
begin
  model := gtk_tree_view_get_model(GTK_TREE_VIEW(ListUseFlags));
  path := gtk_tree_path_new_from_string(path_str);

  gtk_tree_model_get_iter(model, @iter, path);
  gtk_tree_model_get(model, @iter, [0, @checked, -1]);

  checked := not Checked;

  gtk_list_store_set(GTK_LIST_STORE(model), @iter, [0, checked, -1]);

  gtk_tree_path_free(path);
end;

procedure onForm1Destroy(widget : pGtkObject;  data : pgpointer ); cdecl; export;
{ var ... }
begin
  gtk_main_quit();
end;

procedure onButtonUpdateList1Clicked(widget : pGtkButton;  data : pgpointer ); cdecl;
{ var ... }
begin
  gtk_tree_view_set_model(GTK_TREE_VIEW(ListInstalledPackages1), StringListToGtkListStore(Portage.GetInstalledPackages));
end;

procedure onButtonInstall1Clicked(widget : pGtkButton;  data : pgpointer ); cdecl;
var
  model: pGtkTreeModel;
  iter: TGtkTreeIter;
  packages: pGChar;
begin
  if gtk_tree_selection_get_selected(selectionPackages1, @model, @iter) then begin
    gtk_tree_model_get(model, @iter, [0, @packages, -1]);
    gtk_text_buffer_set_text(TextViewBuffer, pGChar('Installing ' + packages + '...' + #10), -1);
    gtk_widget_show_all(Form2);
    gtk_label_set_text(GTK_LABEL(LabelInstallInfo), pGChar('Installing ' + packages + '...'));
    gtk_widget_set_sensitive(ButtonInstallFinished, False);
    gtk_widget_set_sensitive(ButtonInstallCancel, True);
    Portage.Emerge(packages, efInstall);
  end else begin
    gtk_text_buffer_set_text(TextViewBuffer, 'Select the package to be installed first.' + #10, -1);
  end;
  gtk_label_set_text(GTK_LABEL(LabelInstallInfo), pGChar(''));
  onButtonUpdateList1Clicked(nil, nil);
end;

procedure onButtonUninstallClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
var
  model: pGtkTreeModel;
  iter: TGtkTreeIter;
  packages: pGChar;
begin
  if gtk_tree_selection_get_selected(selectionInstalledPackages1, @model, @iter) then begin
    gtk_tree_model_get(model, @iter, [0, @packages, -1]);
    gtk_text_buffer_set_text(TextViewBuffer, pGChar('Uninstalling ' + packages + '...' + #10), -1);
    gtk_window_set_title(GTK_WINDOW(Form2), 'Installing...');
    gtk_widget_show_all(Form2);
    gtk_label_set_text(GTK_LABEL(LabelInstallInfo), pGChar('Uninstalling ' + packages + '...'));
    gtk_widget_set_sensitive(ButtonInstallFinished, False);
    gtk_widget_set_sensitive(ButtonInstallCancel, True);
    Portage.Emerge(packages, efUninstall);
  end else begin
    gtk_text_buffer_set_text(TextViewBuffer, 'Select the package to be uninstalled first.' + #10, -1);
  end;
  gtk_label_set_text(GTK_LABEL(LabelInstallInfo), pGChar(''));
  onButtonUpdateList1Clicked(nil, nil);
end;

procedure onButtonUpdateWorldClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
{ var ... }
begin
  gtk_widget_show_all(Form2);
  gtk_label_set_text(GTK_LABEL(LabelInstallInfo), pGChar('Updating all...'));
  gtk_widget_set_sensitive(ButtonInstallFinished, False);
  Portage.Emerge('world', efUpdate);
  onButtonUpdateList1Clicked(nil, nil);
end;

procedure onButtonUpdateClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
var
  model: pGtkTreeModel;
  iter: TGtkTreeIter;
  packagename: pGChar;
  package, version: string;
begin
  if gtk_tree_selection_get_selected(selectionInstalledPackages1, @model, @iter) then begin
    gtk_tree_model_get(model, @iter, [0, @packagename, -1]);
    Portage.ParsePackageName(packagename, package, version);
    gtk_text_buffer_set_text(TextViewBuffer, pGChar('Updating ' + package + '...' + #10), -1);
    gtk_widget_show_all(Form2);
    gtk_label_set_text(GTK_LABEL(LabelInstallInfo), pGChar('Updating ' + package + '...'));
    gtk_widget_set_sensitive(ButtonInstallFinished, False);
    gtk_widget_set_sensitive(ButtonInstallCancel, True);
    Portage.Emerge(package, efUpdate);
  end else begin
    gtk_text_buffer_set_text(TextViewBuffer, 'Select the package to be updated first.' + #10, -1);
  end;
  gtk_progress_bar_set_text(GTK_PROGRESS_BAR(Progressbar), '');
  onButtonUpdateList1Clicked(nil, nil);
end;

procedure onButtonSearchClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
var
  Results: TStringList;
begin
  Results := TStringList.Create;
  Results.Clear;
  Results := Portage.SearchFromPortage(gtk_entry_get_text(GTK_ENTRY(EditSearch)));
  gtk_tree_view_set_model(GTK_TREE_VIEW(ListPackages2), StringListToGtkListStore(Results));
  Results.Destroy;
end;

procedure onButtonInstall2Clicked(widget : pGtkButton;  data : pgpointer ); cdecl;
var
  model: pGtkTreeModel;
  iter: TGtkTreeIter;
  packages: pGChar;
begin
  if gtk_tree_selection_get_selected(selectionPackages2, @model, @iter) then begin
    gtk_tree_model_get(model, @iter, [0, @packages, -1]);
    gtk_text_buffer_set_text(TextViewBuffer, pGChar('Installing ' + packages + '...' + #10), -1);
    gtk_widget_show_all(Form2);
    gtk_label_set_text(GTK_LABEL(LabelInstallInfo), pGChar('Installing ' + packages + '...'));
    gtk_widget_set_sensitive(ButtonInstallFinished, False);
    gtk_widget_set_sensitive(ButtonInstallCancel, True);
    Portage.emerge(packages, efInstall);
  end else begin
    gtk_text_buffer_set_text(TextViewBuffer, 'Select the package to be installed first.' + #10, -1);
  end;
  gtk_progress_bar_set_text(GTK_PROGRESS_BAR(Progressbar), '');
  onButtonUpdateList1Clicked(nil, nil);
end;

procedure onButtonFecthMirrorsClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
var
  mirrors: String;
begin
  mirrors := Portage.GetMirrors;
  gtk_entry_set_text(GTK_ENTRY(EditPortageMirrors), pGChar(mirrors));
end;

procedure onButtonInstallCancelClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
begin
  Portage.StopEmerge;
  gtk_widget_hide(Form2);
end;

procedure onButtonInstallFinishedClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
begin
  gtk_widget_hide(Form2);
end;

procedure onButtonSyncClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
var
  TextIter: TGtkTextIter;
begin
  gtk_text_buffer_set_text(TextViewBuffer, pGChar('Starting sync...' + #10), -1);
  Portage.Emerge('', efSync);
  gtk_tree_view_set_model(GTK_TREE_VIEW(ListCategorys), StringListToGtkListStore(Portage.ListFilesInPortage('')));
  gtk_text_buffer_get_end_iter(TextViewBuffer, @TextIter);
  gtk_text_buffer_insert(TextViewBuffer, @TextIter, pGChar('Sync finished!' + #10), -1);
end;

procedure onButtonResetSettingsClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
{ var ... }
begin
  Portage.ReadConfig;
  gtk_entry_set_text(GTK_ENTRY(EditPortageDir), pGChar(Portage.Config.PortageDir));
  gtk_entry_set_text(GTK_ENTRY(EditPortageOverlayDir), pGChar(Portage.Config.PortageDirOverlay));
  gtk_entry_set_text(GTK_ENTRY(EditDistfilesDir), pGChar(Portage.Config.DistfilesDir));
  gtk_entry_set_text(GTK_ENTRY(EditPortageMirrors), pGChar(Portage.Config.GentooMirrors));
  gtk_entry_set_text(GTK_ENTRY(EditRSYNCMirrors), pGChar(Portage.Config.SyncMirrors));
  gtk_entry_set_text(GTK_ENTRY(EditBinaryMirrors), pGChar(Portage.Config.BinaryMirrors));
  gtk_entry_set_text(GTK_ENTRY(EditOptimizations), pGChar(Portage.Config.CFlags));
  gtk_entry_set_text(GTK_ENTRY(EditAcceptedKeywords), pGChar(Portage.Config.AcceptKeywords));
  PopulateListUseFlags;
end;

procedure onButtonApplySettingsClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
var
  configs: PortageConfig;
  useflags: String;
  model: pGtkTreeModel;
  iter: TGtkTreeIter;
  selected: GBoolean;
  useflag: pGChar;
  validiter: gBoolean;
begin
  Portage.ReadConfig;
  configs := Portage.Config;
  configs.PortageDir := gtk_entry_get_text(GTK_ENTRY(EditPortageDir));
  configs.PortageDirOverlay := gtk_entry_get_text(GTK_ENTRY(EditPortageOverlayDir));
  configs.DistfilesDir := gtk_entry_get_text(GTK_ENTRY(EditDistfilesDir));
  configs.GentooMirrors := gtk_entry_get_text(GTK_ENTRY(EditPortageMirrors));
  configs.SyncMirrors := gtk_entry_get_text(GTK_ENTRY(EditRSYNCMirrors));
  configs.BinaryMirrors := gtk_entry_get_text(GTK_ENTRY(EditBinaryMirrors));
  configs.CFlags := gtk_entry_get_text(GTK_ENTRY(EditOptimizations));
  configs.AcceptKeywords := gtk_entry_get_text(GTK_ENTRY(EditAcceptedKeywords));

  //get selected use flags
  useflags := '';
  model := gtk_tree_view_get_model(GTK_TREE_VIEW(ListUseFlags));
  validiter := gtk_tree_model_get_iter_first(model, @iter);
  while validiter do begin
    gtk_tree_model_get(model, @iter, [0, @selected, -1]);
    if selected = True then begin
      gtk_tree_model_get(model, @iter, [1, @useflag, -1]);
      useflags := useflags + ' ' + useflag;
    end;
    validiter := gtk_tree_model_iter_next(model, @iter);
  end;
  configs.UseFlags := useflags;

  Portage.WriteConfig(configs);
end;

procedure onPagesSwitchPage(notebook: pGtkNotebook; page: pGtkNotebookPage; page_num: guint; user_data: pgpointer); cdecl;
begin
  if page_num = 3 then begin //Settings
    onButtonResetSettingsClicked(nil, nil);
  end;
end;

procedure onButtonInstallFromEbuildClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
begin
  gtk_entry_set_text(GTK_ENTRY(EditEbuild), '');
  gtk_widget_show_all(Form3);
end;

procedure onButtonEbuildOKClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
var
  ebuildfile,
  category, packagename, packageversion,
  portdir: String;
  file1, file2: Text;
  buffer: Char;
begin
  ReadConfig; //make sure that directory paths are up to date

  ebuildfile := gtk_entry_get_text(GTK_ENTRY(EditEbuild));
  portdir := Portage.Config.PortageDirOverlay;
  category := gtk_entry_get_text(GTK_ENTRY(gtk_bin_get_child(GTK_BIN(ComboPortageCategorys))));
  Portage.ParsePackageName(BaseName(ebuildfile, '.ebuild'), packagename, packageversion);

  if (ExtractFileExt(ebuildfile) <> '.ebuild') or (packagename = '') or (packageversion = '') then begin
    dialog := gtk_message_dialog_new(nil, GTK_DIALOG_MODAL, GTK_MESSAGE_ERROR, GTK_BUTTONS_OK, 'File you specified is not a proper ebuild!');
    gtk_dialog_run(GTK_DIALOG(dialog));
    gtk_widget_hide(Form3);
    gtk_widget_destroy(dialog);
    Exit;
  end;

  if category = '' then begin
    dialog := gtk_message_dialog_new(nil, GTK_DIALOG_MODAL, GTK_MESSAGE_ERROR, GTK_BUTTONS_OK, 'Please specify a category!');
    gtk_dialog_run(GTK_DIALOG(dialog));
    gtk_widget_hide(Form3);
    gtk_widget_destroy(dialog);
    Exit;
  end;

  //create directories for the ebuild
  if not FileExists(portdir + '/' + category) then
    CreateDir(portdir + '/' + category);
  if not FileExists(portdir + '/' + category + '/' + packagename) then
    CreateDir(portdir + '/' + category + '/' + packagename);

  //copy the ebuild
  Assign(file1, ebuildfile);
  Assign(file2, portdir + '/' + category + '/' + packagename + '/' + ExtractFileName(ebuildfile));
  Reset(file1);
  Rewrite(file2);
  if IOResult = 0 then
    while not EoF(file1) do begin
      Read(file1, buffer);
      Write(file2, buffer);
    end
  else begin
      dialog := gtk_message_dialog_new(nil, GTK_DIALOG_MODAL, GTK_MESSAGE_ERROR, GTK_BUTTONS_OK, 'Could not write to Portage''s overlay directory!');
      gtk_dialog_run(GTK_DIALOG(dialog));
      gtk_widget_hide(Form3);
      gtk_widget_destroy(dialog);
  end;
  Flush(file2);
  Close(file1);
  Close(file2);

  //digest the ebuild
  if Shell('ebuild ' + portdir + '/' + category + '/' + packagename + '/' + ExtractFileName(ebuildfile) + ' digest') <> 0 then begin
    dialog := gtk_message_dialog_new(nil, GTK_DIALOG_MODAL, GTK_MESSAGE_ERROR, GTK_BUTTONS_OK, 'Error while digesting ebuild! This might be due the package is unavailable for downloading.');
    gtk_dialog_run(GTK_DIALOG(dialog));
    gtk_widget_hide(Form3);
    gtk_widget_destroy(dialog);
    Exit;
  end;

  //install our newly added ebuild
  gtk_text_buffer_set_text(TextViewBuffer, pGChar('Installing ' + packagename + '...' + #10), -1);
  gtk_widget_show_all(Form2);
  gtk_label_set_text(GTK_LABEL(LabelInstallInfo), pGChar('Installing ' + packagename + '...'));
  gtk_widget_set_sensitive(ButtonInstallFinished, False);
  gtk_widget_set_sensitive(ButtonInstallCancel, True);
  Portage.Emerge(packagename, efInstall);
  gtk_progress_bar_set_text(GTK_PROGRESS_BAR(Progressbar), '');
  onButtonUpdateList1Clicked(nil, nil);

  gtk_widget_hide(Form3);
end;

procedure onButtonEbuildCancelClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
begin
  gtk_entry_set_text(GTK_ENTRY(EditEbuild), '');
  gtk_widget_hide(Form3);
end;

procedure onButtonSelectEbuildClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
begin
  gtk_widget_show_all(FileSelectionEbuild);
end;

procedure onButtonSelectEbuildOKClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
begin
  gtk_entry_set_text(GTK_ENTRY(EditEbuild), gtk_file_selection_get_filename(GTK_FILE_SELECTION(FileSelectionEbuild)));
  gtk_widget_hide(FileSelectionEbuild);
end;

procedure onButtonSelectEbuildCancelClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
begin
  gtk_widget_hide(FileSelectionEbuild);
end;

procedure onButtonEmptyDistfilesDirectoryClicked(widget : pGtkButton;  data : pgpointer ); cdecl;
var
  info : TSearchRec;
begin
  if FindFirst (Config.DistfilesDir + '/*', faAnyFile, Info) = 0 then begin
    repeat
      begin
        if not ((Info.Attr and faDirectory) = faDirectory) and not ((Info.Name = '.') or (Info.Name = '..')) then begin //no directories
	  if not DeleteFile(Portage.Config.DistfilesDir + '/' + Info.Name) then begin //couldn't delete file, show an error message and exit
	    dialog := gtk_message_dialog_new(nil, GTK_DIALOG_MODAL, GTK_MESSAGE_ERROR, GTK_BUTTONS_OK, pGChar('Could not delete file ' + Info.Name + ' in ' + Portage.Config.DistfilesDir + '!'));
	    gtk_dialog_run(GTK_DIALOG(dialog));
	    gtk_widget_destroy(dialog);
	    FindClose(Info);
	    Exit;
	  end;
	end;
      end;
    until FindNext(info) <> 0;
  end;
  FindClose(Info);
end;

procedure onSelectionCategorysChanged(selection: pGtkTreeSelection);
var
  model: pGtkTreeModel;
  iter: TGtkTreeIter;
  category: pGChar;
begin
  if gtk_tree_selection_get_selected(selectionCategorys, @model, @iter) then
    gtk_tree_model_get(model, @iter, [0, @category, -1]);
  gtk_tree_view_set_model(GTK_TREE_VIEW(ListPackages1), StringListToGtkListStore(Portage.ListFilesInPortage(category)));
end;

procedure onSelectionPackages1Changed(selection: pGtkTreeSelection);
var
  model: pGtkTreeModel;
  iter: TGtkTreeIter;
  packagename: pGChar;
  Package: SearchResults;
begin
  if gtk_tree_selection_get_selected(selectionPackages1, @model, @iter) then begin
    gtk_tree_model_get(model, @iter, [0, @packagename, -1]);
    Package := Portage.GetPackageInfo(packagename);
    gtk_label_set_markup(GTK_LABEL(LabelName1), pGChar('<b>' + Package.Name + '</b> (<i>' + Package.DownloadSize + '</i>)'));
    gtk_label_set_markup(GTK_LABEL(LabelHomepage1), pGChar('<span foreground="blue" underline="single">' + Package.Homepage + '</span>'));
    gtk_label_set_text(GTK_LABEL(LabelLatest1), pGChar('Latest version is ' + Package.LatestVersion));
    gtk_label_set_text(GTK_LABEL(LabelInstalled1), pGChar('Installed version is ' + Package.InstalledVersion));
    gtk_label_set_text(GTK_LABEL(LabelDescription1), pGChar(Package.Description));
  end;
end;

procedure onSelectionInstalledPackages1Changed(selection: pGtkTreeSelection);
begin
  //automagic
end;

procedure onSelectionPackages2Changed(selection: pGtkTreeSelection);
var
  model: pGtkTreeModel;
  iter: TGtkTreeIter;
  packagename: pGChar;
  package, version: string;
  Packages: SearchResults;
begin
  if gtk_tree_selection_get_selected(selectionPackages2, @model, @iter) then begin
    gtk_tree_model_get(model, @iter, [0, @packagename, -1]);
    Portage.ParsePackageName(packagename, package, version);
    Packages := Portage.GetPackageInfo(packagename);
    gtk_label_set_markup(GTK_LABEL(LabelName2), pGChar('<b>' + Packages.Name + '</b> (<i>' + Packages.DownloadSize + '</i>)'));
    gtk_label_set_markup(GTK_LABEL(LabelHomepage2), pGChar('<span foreground="blue" underline="single">' + Packages.Homepage + '</span>'));
    gtk_label_set_text(GTK_LABEL(LabelLatest2), pGChar('Latest version is ' + Packages.LatestVersion));
    gtk_label_set_text(GTK_LABEL(LabelInstalled2), pGChar('Installed version is ' + Packages.InstalledVersion));
    gtk_label_set_text(GTK_LABEL(LabelDescription2), pGChar(Packages.Description));
  end;
end;

procedure onSelectionUseFlagsChanged(selection: pGtkTreeSelection);
begin
  //automagic
end;

function onTextViewOutputKeyPressEvent(widget: pGtkWidget; event: pGdkEventKey; user_data: pGPointer): gBoolean;
begin
  //duu sumtin
  Result := True;
end;

function onEditSearchKeyPressEvent(widget: pGtkWidget; event: pGdkEventKey; user_data: pGPointer): gBoolean;
begin
  if event^.keyval = GDK_KEY_Return then begin
    onButtonSearchClicked(nil, nil);
  end;
  Result := False;
end;

procedure EmergeEvent(changed: TEmergeEventType);
var
  TextIter: TGtkTextIter;
begin
  if changed = eeCurrentMessage then begin
    gtk_label_set_text(GTK_LABEL(LabelInstallInfo), pGChar(Portage.InstallInfo.CurrentMessage));
  end;
  if changed = eePackage then begin
    if Portage.InstallInfo.Packages > 0 then gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(Progressbar), GDouble(Portage.InstallInfo.CurrentPackage / Portage.InstallInfo.Packages));
      gtk_window_set_title(GTK_WINDOW(Form2), pGChar('Installing... ' + IntToStr(Portage.InstallInfo.CurrentPackage) + ' / ' + IntToStr(Portage.InstallInfo.Packages)));
      gtk_progress_bar_set_text(GTK_PROGRESS_BAR(ProgressBar), pGChar(IntToStr(Portage.InstallInfo.CurrentPackage) + ' / ' + IntToStr(Portage.InstallInfo.Packages)));
  end;
  if changed = eeOtherMessage then begin
    gtk_text_buffer_get_end_iter(TextViewBuffer, @TextIter);
    gtk_text_buffer_insert(TextViewBuffer, @TextIter, pGChar(Portage.InstallInfo.OtherMessages + #10), -1);
    gtk_text_view_scroll_to_iter(GTK_TEXT_VIEW(TextViewOutput), @TextIter, 0.0, True, 0.0, 1.0);
  end;
  if changed = eeError then begin
    gtk_label_set_markup(GTK_LABEL(LabelInstallInfo), pGChar('<b>Error!</b>'));
    gtk_widget_set_sensitive(ButtonInstallFinished, True);
    gtk_text_buffer_get_end_iter(TextViewBuffer, @TextIter);
    gtk_text_buffer_insert(TextViewBuffer, @TextIter, pGChar('Error occured while working!' + #10), -1);
  end;
  if changed = eeSuccess then begin
    gtk_label_set_markup(GTK_LABEL(LabelInstallInfo), pGChar('<b>Finished succesfully!</b>'));
    gtk_widget_set_sensitive(ButtonInstallFinished, True);
    gtk_widget_set_sensitive(ButtonInstallCancel, False);
    gtk_text_buffer_get_end_iter(TextViewBuffer, @TextIter);
    gtk_text_buffer_insert(TextViewBuffer, @TextIter, pGChar('Finished succesfully!' + #10), -1);
  end;
  if changed = eeIdle then begin
    gtk_progress_bar_pulse(GTK_PROGRESS_BAR(ProgressbarStep));
  end;
  while gtk_events_pending() = 1 do begin
    gtk_main_iteration(); //let gtk's main loop handle the pending events
  end;
end;

var
  i: Integer;
begin
  gtk_init(@argc, @argv);
  glade_init();

  //check if root
  if FpGetEUid <> 0 then begin //we are not the root
    dialog := gtk_message_dialog_new(nil, GTK_DIALOG_MODAL, GTK_MESSAGE_ERROR, GTK_BUTTONS_OK, 'You are not the root! Some parts of UFPortage may not work properly.');
    gtk_dialog_run(GTK_DIALOG(dialog));
    gtk_widget_destroy(dialog);
  end;

  //load the interface
  xml := glade_xml_new('/usr/share/ufportage/ufportage.glade', nil, nil);

  //introduce the widgets
  //main window
  Form1 := glade_xml_get_widget(xml, 'Form1');
  //buttons
  ButtonInstall1 := glade_xml_get_widget(xml, 'ButtonInstall1');
  ButtonSync := glade_xml_get_widget(xml, 'ButtonSync');
  ButtonInstallFromEbuild := glade_xml_get_widget(xml, 'ButtonInstallFromEbuild');
  ButtonUpdateList1 := glade_xml_get_widget(xml, 'ButtonUpdateList1');
  ButtonUninstall := glade_xml_get_widget(xml, 'ButtonUninstall');
  ButtonUpdateWorld := glade_xml_get_widget(xml, 'ButtonUpdateWorld');
  ButtonUpdate := glade_xml_get_widget(xml, 'ButtonUpdate');
  ButtonSearch := glade_xml_get_widget(xml, 'ButtonSearch');
  ButtonInstall2 := glade_xml_get_widget(xml, 'ButtonInstall2');
  ButtonFecthMirrors := glade_xml_get_widget(xml, 'ButtonFecthMirrors');
  ButtonResetSettings := glade_xml_get_widget(xml, 'ButtonResetSettings');
  ButtonApplySettings := glade_xml_get_widget(xml, 'ButtonApplySettings');
  ButtonEmptyDistfilesDirectory := glade_xml_get_widget(xml, 'ButtonEmptyDistfilesDirectory');
  //lists
  ListCategorys := glade_xml_get_widget(xml, 'ListCategorys');
  ListPackages1 := glade_xml_get_widget(xml, 'ListPackages1');
  ListInstalledPackages1 := glade_xml_get_widget(xml, 'ListInstalledPackages1');
  ListPackages2 := glade_xml_get_widget(xml, 'ListPackages2');
  ListUseFlags := glade_xml_get_widget(xml, 'ListUseFlags');
  //labels
  LabelName1 := glade_xml_get_widget(xml, 'LabelName1');
  LabelLatest1 := glade_xml_get_widget(xml, 'LabelLatest1');
  LabelInstalled1 := glade_xml_get_widget(xml, 'LabelInstalled1');
  LabelHomepage1 := glade_xml_get_widget(xml, 'LabelHomepage1');
  LabelDescription1 := glade_xml_get_widget(xml, 'LabelDescription1');
  LabelName2 := glade_xml_get_widget(xml, 'LabelName2');
  LabelLatest2 := glade_xml_get_widget(xml, 'LabelLatest2');
  LabelInstalled2 := glade_xml_get_widget(xml, 'LabelInstalled2');
  LabelHomepage2 := glade_xml_get_widget(xml, 'LabelHomepage2');
  LabelDescription2 := glade_xml_get_widget(xml, 'LabelDescription2');
  //edits
  EditSearch := glade_xml_get_widget(xml, 'EditSearch');
  EditPortageMirrors := glade_xml_get_widget(xml, 'EditPortageMirrors');
  EditRSYNCMirrors := glade_xml_get_widget(xml, 'EditRSYNCMirrors');
  EditAcceptedKeywords := glade_xml_get_widget(xml, 'EditAcceptedKeywords');
  EditOptimizations := glade_xml_get_widget(xml, 'EditOptimizations');
  EditPortageDir := glade_xml_get_widget(xml, 'EditPortageDir');
  EditPortageOverlayDir := glade_xml_get_widget(xml, 'EditPortageOverlayDir');
  EditDistfilesDir := glade_xml_get_widget(xml, 'EditDistfilesDir');
  EditBinaryMirrors := glade_xml_get_widget(xml, 'EditBinaryMirrors');
  //text view
  TextViewOutput := glade_xml_get_widget(xml, 'TextViewOutput');
  //text view's buffer
  TextViewBuffer := gtk_text_view_get_buffer(GTK_TEXT_VIEW(TextViewOutput));
  //pages
  Pages := glade_xml_get_widget(xml, 'Pages');

  //install window
  Form2 := glade_xml_get_widget(xml, 'Form2');
  //label
  LabelInstallInfo := glade_xml_get_widget(xml, 'LabelInstallInfo');
  //buttons
  ButtonInstallFinished := glade_xml_get_widget(xml, 'ButtonInstallFinished');
  ButtonInstallCancel := glade_xml_get_widget(xml, 'ButtonInstallCancel');
  //progressbars
  Progressbar := glade_xml_get_widget(xml, 'Progressbar');
  ProgressbarStep := glade_xml_get_widget(xml, 'ProgressbarStep');

  //install from ebuild window
  Form3 := glade_xml_get_widget(xml, 'Form3');
  //buttons
  ButtonEbuildOK := glade_xml_get_widget(xml, 'ButtonEbuildOK');
  ButtonEbuildCancel := glade_xml_get_widget(xml, 'ButtonEbuildCancel');
  ButtonSelectEbuild := glade_xml_get_widget(xml, 'ButtonSelectEbuild');
  //edits
  EditEbuild := glade_xml_get_widget(xml, 'EditEbuild');
  EditPortageCategorys := glade_xml_get_widget(xml, 'EditPortageCategorys');
  //combobox
  ComboPortageCategorys := glade_xml_get_widget(xml, 'ComboPortageCategorys');

  //file selection dialog
  FileSelectionEbuild := glade_xml_get_widget(xml, 'FileSelectionEbuild');
  //buttons
  ButtonSelectEbuildOK := glade_xml_get_widget(xml, 'ButtonSelectEbuildOK');
  ButtonSelectEbuildCancel := glade_xml_get_widget(xml, 'ButtonSelectEbuildCancel');

  //lets make the treeviews ready
  renderer := gtk_cell_renderer_text_new();
  column := gtk_tree_view_column_new_with_attributes('', renderer, ['text', 0, nil]);
  gtk_tree_view_append_column(GTK_TREE_VIEW(ListCategorys), column);
  renderer := gtk_cell_renderer_text_new();
  column := gtk_tree_view_column_new_with_attributes('', renderer, ['text', 0, nil]);
  gtk_tree_view_append_column(GTK_TREE_VIEW(ListPackages1), column);
  renderer := gtk_cell_renderer_text_new();
  column := gtk_tree_view_column_new_with_attributes('', renderer, ['text', 0, nil]);
  gtk_tree_view_append_column(GTK_TREE_VIEW(ListInstalledPackages1), column);
  renderer := gtk_cell_renderer_text_new();
  column := gtk_tree_view_column_new_with_attributes('', renderer, ['text', 0, nil]);
  gtk_tree_view_append_column(GTK_TREE_VIEW(ListPackages2), column);
  renderer := gtk_cell_renderer_toggle_new();
  g_signal_connect(renderer, 'toggled', G_CALLBACK(@ToggleUseFlags), gtk_tree_view_get_model(GTK_TREE_VIEW(ListUseFlags)));
  column := gtk_tree_view_column_new_with_attributes('', renderer, ['active', 0, nil]);
  gtk_tree_view_append_column(GTK_TREE_VIEW(ListUseFlags), column);
  renderer := gtk_cell_renderer_text_new();
  column := gtk_tree_view_column_new_with_attributes('Flag', renderer, ['text', 1, nil]);
  gtk_tree_view_append_column(GTK_TREE_VIEW(ListUseFlags), column);
  renderer := gtk_cell_renderer_text_new();
  column := gtk_tree_view_column_new_with_attributes('Description', renderer, ['text', 2, nil]);
  gtk_tree_view_append_column(GTK_TREE_VIEW(ListUseFlags), column);
  selectionCategorys := gtk_tree_view_get_selection(GTK_TREE_VIEW(ListCategorys));
  selectionPackages1 := gtk_tree_view_get_selection(GTK_TREE_VIEW(ListPackages1));
  selectionInstalledPackages1 := gtk_tree_view_get_selection(GTK_TREE_VIEW(ListInstalledPackages1));
  selectionPackages2 := gtk_tree_view_get_selection(GTK_TREE_VIEW(ListPackages2));
  selectionUseFlags := gtk_tree_view_get_selection(GTK_TREE_VIEW(ListUseFlags));

  //connect the signals in the interface
  g_signal_connect(gpointer(Form1), 'destroy', GTK_SIGNAL_FUNC(@onForm1Destroy), nil);
  g_signal_connect(gpointer(ButtonSync), 'clicked', GTK_SIGNAL_FUNC(@onButtonSyncClicked), nil);
  g_signal_connect(gpointer(ButtonInstall1), 'clicked', GTK_SIGNAL_FUNC(@onButtonInstall1Clicked), nil);
  g_signal_connect(gpointer(ButtonInstallFromEbuild), 'clicked', GTK_SIGNAL_FUNC(@onButtonInstallFromEbuildClicked), nil);
  g_signal_connect(gpointer(ButtonUpdateList1), 'clicked', GTK_SIGNAL_FUNC(@onButtonUpdateList1Clicked), nil);
  g_signal_connect(gpointer(ButtonUninstall), 'clicked', GTK_SIGNAL_FUNC(@onButtonUninstallClicked), nil);
  g_signal_connect(gpointer(ButtonUpdateWorld), 'clicked', GTK_SIGNAL_FUNC(@onButtonUpdateWorldClicked), nil);
  g_signal_connect(gpointer(ButtonUpdate), 'clicked', GTK_SIGNAL_FUNC(@onButtonUpdateClicked), nil);
  g_signal_connect(gpointer(ButtonSearch), 'clicked', GTK_SIGNAL_FUNC(@onButtonSearchClicked), nil);
  g_signal_connect(gpointer(ButtonInstall2), 'clicked', GTK_SIGNAL_FUNC(@onButtonInstall2Clicked), nil);
  g_signal_connect(gpointer(ButtonFecthMirrors), 'clicked', GTK_SIGNAL_FUNC(@onButtonFecthMirrorsClicked), nil);
  g_signal_connect(gpointer(ButtonResetSettings), 'clicked', GTK_SIGNAL_FUNC(@onButtonResetSettingsClicked), nil);
  g_signal_connect(gpointer(ButtonApplySettings), 'clicked', GTK_SIGNAL_FUNC(@onButtonApplySettingsClicked), nil);
  g_signal_connect(gpointer(ButtonInstallCancel), 'clicked', GTK_SIGNAL_FUNC(@onButtonInstallCancelClicked), nil);
  g_signal_connect(gpointer(ButtonInstallFinished), 'clicked', GTK_SIGNAL_FUNC(@onButtonInstallFinishedClicked), nil);
  g_signal_connect(gpointer(ButtonEbuildOK), 'clicked', GTK_SIGNAL_FUNC(@onButtonEbuildOKClicked), nil);
  g_signal_connect(gpointer(ButtonEbuildCancel), 'clicked', GTK_SIGNAL_FUNC(@onButtonEbuildCancelClicked), nil);
  g_signal_connect(gpointer(ButtonSelectEbuild), 'clicked', GTK_SIGNAL_FUNC(@onButtonSelectEbuildClicked), nil);
  g_signal_connect(gpointer(ButtonSelectEbuildOK), 'clicked', GTK_SIGNAL_FUNC(@onButtonSelectEbuildOKClicked), nil);
  g_signal_connect(gpointer(ButtonSelectEbuildCancel), 'clicked', GTK_SIGNAL_FUNC(@onButtonSelectEbuildCancelClicked), nil);
  g_signal_connect(gpointer(ButtonEmptyDistfilesDirectory), 'clicked', GTK_SIGNAL_FUNC(@onButtonEmptyDistfilesDirectoryClicked), nil);
  g_signal_connect(gpointer(Pages), 'switch_page', GTK_SIGNAL_FUNC(@onPagesSwitchPage), nil);
  g_signal_connect(gpointer(TextViewOutput), 'key_press_event', GTK_SIGNAL_FUNC(@onTextViewOutputKeyPressEvent), nil);
  g_signal_connect(gpointer(EditSearch), 'key_press_event', GTK_SIGNAL_FUNC(@onEditSearchKeyPressEvent), nil);

  //connect the selection_changed signals
  g_signal_connect(gpointer(selectionCategorys), 'changed', GTK_SIGNAL_FUNC(@onSelectionCategorysChanged), nil);
  g_signal_connect(gpointer(selectionPackages1), 'changed', GTK_SIGNAL_FUNC(@onSelectionPackages1Changed), nil);
  g_signal_connect(gpointer(selectionInstalledPackages1), 'changed', GTK_SIGNAL_FUNC(@onSelectionInstalledPackages1Changed), nil);
  g_signal_connect(gpointer(selectionPackages2), 'changed', GTK_SIGNAL_FUNC(@onSelectionPackages2Changed), nil);
  //signal of something going on in Emerge
  Portage.EmergeEvent := @EmergeEvent;

  //update the configs
  Portage.ReadConfig;

  //fill the category list
  gtk_tree_view_set_model(GTK_TREE_VIEW(ListCategorys), StringListToGtkListStore(Portage.ListFilesInPortage('')));
  //fill the "installed packages" lists
  gtk_tree_view_set_model(GTK_TREE_VIEW(ListInstalledPackages1), StringListToGtkListStore(Portage.GetInstalledPackages));
  //fill the list of use flags
  PopulateListUseFlags;

  //fill the combobox with categorys
  gtk_combo_box_set_model(GTK_COMBO_BOX(ComboPortageCategorys), StringListToGtkListStore(Portage.ListFilesInPortage('')));
  gtk_combo_box_entry_set_text_column(GTK_COMBO_BOX_ENTRY(ComboPortageCategorys), 0);

  //start the event loop
  gtk_main();

end.
