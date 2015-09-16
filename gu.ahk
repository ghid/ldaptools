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
#Include *i %A_ScriptDir%\gu.versioninfo
#Include d:\work\ahk\projects\Lib2\ldap.ahk

Main:
	_main := new Logger("app.gu.Main")
	
	global G_count, G_lower, G_upper, G_short, G_output, G_append, G_host := "LX150W05.viessmann.com", G_help, G_sort, G_version, G_nested_groups, G_groupfilter := "groupOfNames", G_regex, G_out_file, G_out_h := 0, G_refs, G_color, G_max_nested_lv := 32

	global G_LDAP_CONN := 0

	global G_dn, G_cn, G_filter := "*"
	global G_member_list := []
	global G_scanned_group := []
	global G_out_file_name := ""

	global RC_OK             := -1
	     , RC_MISSING_ARG    := -2
	     , RC_INVALID_ARGS   := -3
		 , RC_CYCLE_DETECTED := -4
		 , RC_CN_NOT_FOUND   := -5
		 , RC_CN_AMBIGOUS    := -6

	rc := RC_OK

	op := new OptParser("gu [-a <filename> | -o <filename>] [options] <cn> [filter]",, "GU_OPTIONS")
	op.Add(new OptParser.String("a", "append", G_append, "file-name", "Append result to existing file"))
	op.Add(new OptParser.String("o", "", G_output, "file-name", "Write result to file"))
	op.Add(new OptParser.Group("`nOptions"))
	op.Add(new OptParser.Boolean("1", "short", G_short, "Display common names instead of the DN"))
	op.Add(new OptParser.Boolean("c", "count", G_count, "Display number of hits"))
	op.Add(new OptParser.Boolean("e", "regex", G_regex, "Use a regular expression to filter the result set (see also http://ahkscript.org/docs/misc/RegEx-QuickRef.htm)"))
	op.Add(new OptParser.String("h", "host", G_host, "host-name", "Hostname of the LDAP-Server (default=" G_host ")",, G_host, G_host))
	op.Add(new OptParser.Boolean("l", "lower", G_lower, "Display result in lower case characters"))
	op.Add(new OptParser.Boolean("u", "upper", G_upper, "Display result in upper case characters"))
	op.Add(new OptParser.Boolean("r", "refs", G_refs, "Display relations"))
	op.Add(new OptParser.Boolean("s", "sort", G_sort, "Sort result"))
	op.Add(new OptParser.Boolean(0, "color", G_color, "Colored output (deactivated by default if -a or -o option is set)",OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE, -1, true))
	op.Add(new OptParser.Boolean(0, "ibm", G_ibm, "Only chase groups which implement objectclass ibm-nestedGroup"))
	op.Add(new OptParser.String(0, "max-nested-level", G_max_nested_lv, "n", "Defines, which recursion depth terminates the process (default=32)",, G_max_nested_lv, G_max_nested_lv))
	op.Add(new OptParser.Boolean(0, "env", env_dummy, "Ignore environment variable GI_OPTIONS", OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE))
	op.Add(new OptParser.Boolean(0, "version", G_version, "Print version info"))
	op.Add(new OptParser.Boolean(0, "help", G_help, "Print help", OptParser.OPT_HIDDEN))

	try {
		args := op.Parse(System.vArgs)

		if (_main.Logs(Logger.Finest)) {
			_main.Finest("G_count", G_count)
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
			_main.Finest("G_ibm", G_ibm)
			_main.Finest("G_max_nested_lv", G_max_nested_lv)
			_main.Finest("G_version", G_version)
			_main.Finest("G_help", G_help)
		}

		if (G_help) {
			Ansi.WriteLine(op.Usage())
			exitapp _main.Exit(RC_OK)
		} else if (G_version) {
			Ansi.WriteLine(G_VERSION_INFO.NAME "/" G_VERSION_INFO.ARCH "-b" G_VERSION_INFO.BUILD)
			exitapp _main.Exit(RC_OK)
		}

		if (args.MaxIndex() < 1) {
			throw Exception("error: Missing argument",, RC_MISSING_ARG)
		}

		OptParser.TrimArg(G_max_nested_lv)
		OptParser.TrimArg(G_output)
		OptParser.TrimArg(G_append)
		if (_main.Logs(Logger.Finest)) {
			_main.Finest("G_append", G_append)
			_main.Finest("G_output", G_output)
			_main.Finest("G_max_nested_lv", G_max_nested_lv)
		}
		if (G_output && G_append) {
			throw Exception("error: Options '-o' and '-a' cannot be used together",, RC_INVALID_ARGS)
		}

		if (G_upper && G_lower) {
			throw Exception("error: Options '-l' and '-u' cannot be used together",, RC_INVALID_ARGS)
		}

		G_cn := args[1]
		if (args.MaxIndex() = 2)
			G_filter := args[2]

		if (_main.Logs(Logger.Finest)) {
			_main.Finest("G_cn", G_cn)
			_main.Finest("G_filter", G_filter)
		}

		if (G_sort || G_output || G_append) {
			G_out_h := FileOpen(A_Temp "\__gu__.dat", "w`n")
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

		; dn := ldap_get_dn("(cn=" args[1] ")")
		
		; if (_main.Logs(Logger.Finest)) {
			; _main.Finest("dn", dn)
		; }
		; Ansi.WriteLine(dn, true)
		rc := ldap_get_user_list(args[1])	

		; Handle sort and/or output options
		; ---------------------------------
		if (G_out_h)
			G_out_h.Close()
		if (_main.Logs(Logger.Finest)) {
			_main.Finest("G_out_h", G_out_h)
		}
		if (G_out_h) {
			h_gu := FileOpen(A_Temp "\__gu__.dat", "r`n")
			if (_main.Logs(Logger.Finest)) {
				_main.Finest("h_gu", h_gu)
				_main.Finest("h_gu.Length", h_gu.Length)
			}
			content := h_gu.Read(h_gu.Length)
			h_gu.Close()
			; FileRead content, %A_Temp%\__gu__.dat
			if (G_sort)
				Sort content
			FileDelete %A_Temp%\__gu__.dat
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

		if (G_count)
			Ansi.WriteLine("`n" rc " Hit(s)")
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

format_output(text, ref) {
	_log := new Logger("app.gu." A_ThisFunc)
	
	if (_log.Logs(Logger.Input)) {
		_log.Input("text", text)
		_log.Input("ref", ref)
	}

	if (G_refs) {
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
	_log := new Logger("app.gu." A_ThisFunc)
	
	if (_log.Logs(Logger.Input)) {
		_log.Input("text", text)
	}

	res := true
	try {
		if (res := text.Filter(G_filter, G_regex))
			if (G_out_h)
				G_out_h.WriteLine(text)
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

ldap_get_user_list(groupcn) {
	_log := new Logger("app.gu." A_ThisFunc)

	static n := 0
	static l := 0
	static user_list := []
	
	if (_log.Logs(Logger.Input)) {
		_log.Input("groupcn", groupcn)
	}

	if (_log.Logs(Logger.Finest)) {
		_log.Finest("G_groupfilter", G_groupfilter)
	}
	G_LDAP_CONN.Search("dc=viessmann,dc=net", "(&(objectclass=" G_groupfilter ")(cn=" groupcn "))")
	iCount := G_LDAP_CONN.CountEntries()
	if (_log.Logs(Logger.Finest)) {
		_log.Finest("iCount", iCount)
	}
	loop %iCount% {
		if (A_Index = 1)
			member := G_LDAP_CONN.FirstEntry()
		else
			member := G_LDAP_CONN.NextEntry(member)
		pAttr := G_LDAP_CONN.FirstAttribute(member)
		if (_log.Logs(Logger.Finest)) {
			_log.Finest("pAttr", pAttr)
		}
		while (pAttr) {
			System.StrCpy(pAttr, stAttr)
			if (_log.Logs(Logger.Finest)) {
				_log.Finest("stAttr", stAttr)
			}
			if (stAttr = "member") {
				pValues := G_LDAP_CONN.GetValues(member, pAttr)
				aValues := System.PtrListToStrArray(pValues)
				if (_log.Logs(Logger.Finest)) {
					_log.Finest("aValues:`n" LoggingHelper.Dump(aValues))
				}
				loop % aValues.MaxIndex() {
					if (RegExMatch(aValues[A_Index], "i)cn=(.+)\w*,\w*ou=.+\w*,.*$", $)) {
						if (_log.Logs(Logger.Finest)) {
							_log.Finest("$1", $1)
						}
						if (ldap_is_group($1)) {
							l++
							if (l>G_max_nested_lv) {
								_log.Finest("groupcn", groupcn)
								throw _log.Exit(Exception("error: Cyclic reference detected: `n`t" $ "`n`t<- " groupcn,, RC_CYCLE_DETECTED))
							}
							ldap_get_user_list($1)
							l--
						} else {
							if (user_list[$] = "" || G_refs) {
								if (output(format_output($, (G_short ? groupcn : ldap_get_dn("cn=" groupcn)))))
									n++
								user_list[$] := 1
							}
						}
					}
				}
				break
			}
			pAttr := G_LDAP_CONN.NextAttribute(member)
			if (_log.Logs(Logger.Finest)) {
				_log.Finest("pAttr", pAttr)
			}
		}
	}

	if (_log.Logs(Logger.Finest)) {
		_log.Finest("user_list:`n" LoggingHelper.Dump(user_list))
	}
	
	return _log.Exit(n)
}

ldap_is_group(cn) {
	_log := new Logger("app.gu." A_ThisFunc)
	
	if (_log.Logs(Logger.Input)) {
		_log.Input("cn", cn)
	}

	G_LDAP_CONN.Search("dc=viessmann,dc=net", "(&(objectclass=" G_groupfilter ")(cn=" cn "))")
	if (G_LDAP_CONN.CountEntries())
		return _log.Exit(true)	
	else	
		return _log.Exit(false)
}

ldap_get_dn(ldapFilter) {
	_log := new Logger("app.gu." A_ThisFunc)
	
	if (_log.Logs(Logger.Input)) {
		_log.Input("ldapFilter", ldapFilter)
	}

	G_LDAP_CONN.Search("dc=viessmann,dc=net", ldapFilter)
	iCount := G_LDAP_CONN.CountEntries()
	if (_log.Logs(Logger.Finest)) {
		_log.Finest("iCount", iCount)
	}
	if (iCount = 0) {
		throw _log.Exit(Exception("error: cn not found """ ldapFilter """",, RC_CN_NOT_FOUND))
	} else if (iCount > 1) {
		throw _log.Exit(Exception("error: cn is ambigous (" iCount ") """ ldapFilter """",, RC_CN_AMBIGOUS))
	}
	entry := G_LDAP_CONN.FirstEntry()

	return _log.Exit(G_LDAP_CONN.GetDn(entry))
}

; vim: ts=4:sts=4:sw=4:tw=0:noet
