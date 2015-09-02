#NoEnv
#MaxHotkeysPerInterval 99000000
#HotkeyInterval 99000000
#KeyHistory 0
ListLines Off
Process, Priority, , H ;if unstable, comment or remove this line
SetBatchLines, -1
SetKeyDelay, -1, -1
SetMouseDelay, -1
SetDefaultMouseSpeed, 0
SetWinDelay, -1
SetControlDelay, -1
SendMode Input

#Include <logging>
#Include <system>
#Include <optparser>
#Include <ansi>
#Include <string>
#Include *i %A_ScriptDir%\gi.versioninfo
#Include d:\work\ahk\projects\Lib2\ldap.ahk

Main:
	_main := new Logger("app.gi.Main")
	
	global G_lower, G_upper, G_short, G_verbose, G_output, G_append, G_host := "LX150W05.viessmann.com", G_help, G_sort, G_version, G_nested_groups, G_groupfilter := "groupOfNames", G_regex, G_out_file, G_out_h := 0, G_refs, G_color

	global G_LDAP_CONN := 0

	global G_dn, G_cn, G_filter := "*"
	global G_member_list := []
	global G_scanned_group := []
	global G_ref := []
	global G_out_file_name := ""

	rc := 0

	op := new OptParser("gi [-a <dateiname> | -o <dateiname>] [options] <cn> [filter]")
	op.Add(new OptParser.String("a", "append", G_append, "file-name", "An vorhandene Datei anhängen"))
	op.Add(new OptParser.String("o", "", G_output, "file-name", "In Datei ausgeben"))
	op.Add(new OptParser.Group("`nOptions"))
	op.Add(new OptParser.Boolean("1", "short", G_short, "Nur Gruppenname ausgeben anstelle des DN"))
	op.Add(new OptParser.Boolean("e", "regex", G_regex, "Verwendet einen regulären Ausdruck zum filtern des Ergebnisses (siehe auch http://ahkscript.org/docs/misc/RegEx-QuickRef.htm)"))
	op.Add(new OptParser.String("h", "host", G_host, "host-name", "Hostname des LDAP-Servers (default=" G_host ")",, G_host, G_host))
	op.Add(new OptParser.Boolean("l", "lower", G_lower, "Ergebnis in Kleinbuchstaben ausgeben"))
	op.Add(new OptParser.Boolean("u", "upper", G_upper, "Ergebnis in Großbuchstaben ausgeben"))
	op.Add(new OptParser.Boolean("r", "refs", G_refs, "Referenzen auflisten"))
	op.Add(new OptParser.Boolean("s", "sort", G_sort, "Ergebnis sortiert ausgeben"))
	op.Add(new OptParser.Boolean(0, "color", G_color, "Farbige Textausgabe (wird bei -a oder -o deaktiviert)",OptParser.OPT_NEG, -1, true))
	op.Add(new OptParser.Boolean("v", "verbose", G_verbose, "Verarbeitungsprotokoll ausgeben"))
	op.Add(new OptParser.Boolean(0, "ibm", G_ibm, "Nur Einträge mit objectClass ibm-nestedGroup berücksichtigen"))
	op.Add(new OptParser.Boolean(0, "version", G_version, "Print version info"))
	op.Add(new OptParser.Boolean(0, "help", G_help, "Print help", OptParser.OPT_HIDDEN))

	try {
		args := op.Parse(System.vArgs)

		if (_main.Logs(Logger.Finest)) {
			_main.Finest("G_refs", G_refs)
			_main.Finest("G_short", G_short)
			_main.Finest("G_append", G_append)
			_main.Finest("G_output", G_output)
			_main.Finest("G_host", G_host)
			_main.Finest("G_color", G_color)
			_main.Finest("G_regex", G_regex)
			_main.Finest("G_lower", G_lower)
			_main.Finest("G_upper", G_upper)
			_main.Finest("G_sort", G_sort)
			_main.Finest("G_verbose", G_verbose)
			_main.Finest("G_ibm", G_ibm)
			_main.Finest("G_version", G_version)
			_main.Finest("G_help", G_help)
		}

		if (G_help) {
			Ansi.WriteLine(op.Usage())
			exitapp _main.Exit()
		} else if (G_version) {
			Ansi.WriteLine(G_VERSION_INFO.NAME "/" G_VERSION_INFO.ARCH "-b" G_VERSION_INFO.BUILD)
			exitapp _main.Exit()
		}

		if (args.MaxIndex() < 1) {
			throw Exception("error: Missing argument",, -2)
		; } else if ((!G_refs && args.MaxIndex() > 2) || (G_refs && args.MaxIndex() > 1)) {
		; 	throw Exception("error: Invalid argument(s)",, -2)
		}

		OptParser.TrimArg(G_output)
		OptParser.TrimArg(G_append)
		if (G_output && G_append) {
			throw Exception("error: Options '-o' and '-a' cannot be used together",, -3)
		}

		if (G_upper && G_lower) {
			throw Exception("error: Options '-l' and '-u' cannot be used together",, -3)
		}

		G_cn := args[1]
		if (args.MaxIndex() = 2)
			G_filter := args[2]

		if (_main.Logs(Logger.Finest)) {
			_main.Finest("G_host", G_host)
			_main.Finest("G_lower", G_lower)
			_main.Finest("G_upper", G_upper)
			_main.Finest("G_short", G_short)
			_main.Finest("G_verbose", G_verbose)
			_main.Finest("G_output", G_output)
			_main.Finest("G_append", G_append)
			_main.Finest("G_sort", G_sort)
			_main.Finest("G_regex", G_regex)
			_main.Finest("G_ibm", G_ibm)
			_main.Finest("G_version", G_version)
			_main.Finest("G_help", G_help)
			_main.Finest("G_cn", G_cn)
			_main.Finest("G_filter", G_filter)
		}

		if (G_sort || G_output || G_append) {
			G_out_h := FileOpen(A_Temp "\__gi__.dat", "w`n")
			if ((G_output || G_append) && G_color <> true) {
				G_color := false
				if (_main.Logs(Logger.Warning)) {
					_main.Warning("G_color has been set to false because of file output", G_color)
				}
			}
		}

		if (G_ibm) {
			G_groupfilter := "ibm-nestedGroup"
		}
		if (_main.Logs(Logger.Finest)) {
			_main.Finest("G_groupfilter", G_groupfilter)
		}

		Ansi.Write("Connecting to " G_host " ... ")
		G_LDAP_CONN := new Ldap(G_host)
		G_LDAP_CONN.Connect()
		Ansi.WriteLine("Ok.")

		dn := ldap_get_dn("(cn=" args[1] ")")
		
		if (_main.Logs(Logger.Finest)) {
			_main.Finest("dn", dn)
		}
		Ansi.WriteLine(dn, true)
		get_member_list(dn)
		i := 1
		rc := 0
		while (i <= G_member_list.MaxIndex()) {
			group := G_member_list[i]
			_main.Info("Scanning #" i " " group)
			if (_main.Logs(Logger.Finest)) {
				_main.Finest("G_member_list.MaxIndex()", G_member_list.MaxIndex())
				_main.Finest("i", i)
				_main.Finest("group", group)
			}
			if (G_refs || !G_scanned_group[group]) {
				G_scanned_group[group] := 1
				if (output(format_output(group)))
					rc++
				get_member_list(group)
			}
			i++
		}

		; Handle sort and/or output options
		; ---------------------------------
		if (G_out_h)
			G_out_h.Close()
		if (_main.Logs(Logger.Finest)) {
			_main.Finest("G_out_h", G_out_h)
		}
		if (G_out_h) {
			h_gi := FileOpen(A_Temp "\__gi__.dat", "r`n")
			if (_main.Logs(Logger.Finest)) {
				_main.Finest("h_gi", h_gi)
				_main.Finest("h_gi.Length", h_gi.Length)
			}
			content := h_gi.Read(h_gi.Length)
			h_gi.Close()
			; FileRead content, %A_Temp%\__gi__.dat
			if (G_sort)
				Sort content
			FileDelete %A_Temp%\__gi__.dat
		}

		if (G_append) {
			file_name := G_append
		} else if (G_output) {
			if (FileExist(G_output))
				FileDelete %G_output%
			file_name := G_output
		} else {
			file_name := "*"
		}
		if (_main.Logs(Logger.Info)) {
			_main.Info("file_name", file_name)
		}
		if (file_name = "*")
			Ansi.Write(content)
		else
			FileAppend %content%, %file_name%
		content := ""

	} catch _ex {
		if (_main.Logs(Logger.Info)) {
			_main.Info("_ex", _ex)
		}
		Ansi.WriteLine(_ex.Message)
		Ansi.WriteLine(op.Usage())
		rc := _ex.Extra
	} finally {
		_main.Info("Executing finally block")
		if (G_LDAP_CONN)
			G_LDAP_CONN.Unbind()
		if (G_out_h)
			G_out_h.Close()
	}
	
exitapp	_main.Exit(rc)

format_output(text) {
	_log := new Logger("app.gi." A_ThisFunc)
	
	if (_log.Logs(Logger.Input)) {
		_log.Input("text", text)
		_log.Finest("ref", ref)
	}

	if (G_refs) {
		ref := G_ref[text]
		if (G_short)
			if (RegExMatch(ref, "^.*?=(.*?),.*$", $))
				ref := $1
	} else
		ref := ""
	if (G_short) {
		if (RegExMatch(text, "^.*?=(.*?),.*$", $))
			text := $1	
	}
	if (G_upper) {
		text := text.Upper()
		ref := ref.Upper()
	} else if (G_lower) {
		text := text.Lower()
		ref := ref.Lower()
	}

	if (G_color) {
		text := RegExReplace(text, "(?P<attr>\w+=)", Ansi.SetGraphic(Ansi.FOREGROUND_GREEN, Ansi.ATTR_BOLD) "${attr}" Ansi.SetGraphic(Ansi.ATTR_OFF))
		if (G_refs)
			ref := Ansi.SetGraphic(Ansi.FOREGROUND_RED, Ansi.ATTR_BOLD) "  <-(" RegExReplace(ref, "(?P<attr>\w+=)", Ansi.SetGraphic(Ansi.FOREGROUND_GREEN, Ansi.ATTR_BOLD) "${attr}" Ansi.SetGraphic(Ansi.ATTR_OFF)) Ansi.SetGraphic(Ansi.FOREGROUND_RED, Ansi.ATTR_BOLD) ")" Ansi.SetGraphic(Ansi.ATTR_OFF)
	} else
		if (G_refs)
			ref := "  <-(" ref ")"

	return _log.Exit(text ref)
}

output(text) {
	_log := new Logger("app.gi." A_ThisFunc)
	
	if (_log.Logs(Logger.Input)) {
		_log.Input("text", text)
	}

	res := true
	try {
		if (res := text.Filter(G_filter, G_regex))
			if (G_out_h)
				G_out_h.WriteLine("   " text)
			else
				Ansi.WriteLine("   " text, true)
	} catch _ex {
		if (_log.Logs(Logger.Warning)) {
			_log.Warning(_ex.Message)
			res := false
		}
	}
	
	return _log.Exit(res)
}

ldap_get_dn(ldapFilter) {
	_log := new Logger("app.gi." A_ThisFunc)
	
	if (_log.Logs(Logger.Input)) {
		_log.Input("ldapFilter", ldapFilter)
	}

	G_LDAP_CONN.Search("dc=viessmann,dc=net", ldapFilter)
	iCount := G_LDAP_CONN.CountEntries()
	if (_log.Logs(Logger.Finest)) {
		_log.Finest("iCount", iCount)
	}
	if (iCount = 0) {
		throw _log.Exit(Exception("error: cn not found """ ldapFilter """",, -3)) ; ToDo: Fehlercode durch Konstante ersetzen
	} else if (iCount > 1) {
		throw _log.Exit(Exception("error: cn is ambigous (" iCount ") """ ldapFilter """",, -4)) ; ToDo: Fehlercode durch Konstante ersetzen
	}
	entry := G_LDAP_CONN.FirstEntry()

	return _log.Exit(G_LDAP_CONN.GetDn(entry))
}

get_member_list(memberdn) {
	_log := new Logger("app.gi." A_ThisFunc)
	
	if (_log.Logs(Logger.Input)) {
		_log.Input("memberdn", memberdn)
	}
	G_LDAP_CONN.Search("dc=viessmann,dc=net", "(&(objectclass=" G_groupfilter ")(member=" memberdn "))")
	iCount := G_LDAP_CONN.CountEntries()
	if (_log.Logs(Logger.Finest)) {
		_log.Finest("iCount", iCount)
	}
	loop %iCount% {
		if (A_Index = 1)
			entry := G_LDAP_CONN.FirstEntry()
		else
			entry := G_LDAP_CONN.NextEntry(entry)
		dn := G_LDAP_CONN.GetDn(entry)
		if (G_refs)
			G_ref[dn] := memberdn
		G_member_list.Insert(dn)
	}

	return _log.Exit()
}
