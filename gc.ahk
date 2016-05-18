; ahk: x86
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
#Include *i %A_ScriptDir%\gc.versioninfo
#Include <ldap>
#Include <arrays>
#Include <pager>

init:
	_init := new Logger("app.gc.Init")

	global G_help, G_version, G_ldap_server := "localhost", G_ldap_port := 389, G_base_dn, G_ldap_port, G_print_search_failures := false, G_pager := true, G_ldif, G_group_pattern := "*"

	global G_status_groups := 0, G_status_current := 0

	rc := 0
	
	op := new OptParser("gc [-p <port>] [<ldap-server> [<group-name-pattern>]]")
	op.Add(new OptParser.String("p", "port", G_ldap_port, "portnum", "Port number of the LDAP server (default=" G_ldap_port ")",, G_ldap_port, G_ldap_port))
	op.Add(new OptParser.String("b", "base-dn", G_base_dn, "basedn", "Provide a base dn to start the search"))
	op.Add(new OptParser.String(0, "ldif", G_ldif, "filename", "Generate an LDIF file to add missing ibm-memberGroup entries", OptParser.Opt_ARG, G_ldif, G_ldif))
	op.Add(new OptParser.Boolean(0, "pager", G_pager, "Enable paging (default: on)", OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE, G_pager, G_pager))
	op.Add(new OptParser.Boolean(0, "print-search-failures", G_print_search_failures, "Print if a search failed (default: off)", OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE))
	op.Add(new OptParser.Boolean(0, "version", G_version, "Print version info"))
	op.Add(new OptParser.Boolean("h", "help", G_help, "Print help"))


	try {
		args := op.Parse(System.vArgs)

		OptParser.TrimArg(G_ldap_port)
		OptParser.TrimArg(G_base_dn)
		OptParser.TrimArg(G_ldif)

		if (_init.Logs(Logger.Finest)) {
			_init.Finest("G_ldap_port", G_ldap_port)
			_init.Finest("G_base_dn", G_base_dn)
			_init.Finest("G_ldif", G_ldif)
			_init.Finest("G_pager", G_pager)
			_init.Finest("G_print_search_failures", G_print_search_failures)
			_init.Finest("G_help", G_help)
			_init.Finest("G_version", G_version)
		}

		if (G_help) {
			Ansi.WriteLine(op.Usage())
			exitapp _init.Exit(0)
		}
		if (G_version) {
			Ansi.WriteLine(G_VERSION_INFO.NAME "/" G_VERSION_INFO.ARCH "-b" G_VERSION_INFO.BUILD)
			exitapp _init.Exit(0)
		}

		if (args.MaxIndex() > 2)
			throw Exception("error: Too many arguments")
		else if (args.MaxIndex() >= 1) {
			G_ldap_server := args[1]
			if (args.MaxIndex() = 2)
				G_group_pattern := args[2]
		}
		if (_init.Logs(Logger.Finest)) {
			_init.Finest("G_ldap_server", G_ldap_server)
			_init.Finest("G_group_pattern", G_group_pattern)
		}

		if (!G_pager)
			Pager.bEnablePager := false

		rc := main()

	} catch _init_ex {
		if (_init.Logs(Logger.Info)) {
			_init.Finest("_init_ex", _init_ex)	
		}
		Ansi.WriteLine(_init_ex.Message)
		Ansi.WriteLine(op.Usage())
	}
exitapp _init.Exit(rc)

main() {
	_log := new Logger("app.gc." A_ThisFunc)

	ldap_conn := 0
	ldif_file := 0

	try {
		Ansi.Write("Connection to " G_ldap_server ":" G_ldap_port " ... ", true)
		ldap_conn := new Ldap(G_ldap_server, G_ldap_port)
		if (ldap_conn.Connect() = 0) {
			Ansi.WriteLine("Ok.", true)
			if (G_ldif) {
				Ansi.WriteLine("Generate LDIF file: " G_ldif)
				ldif_file := FileOpen(G_ldif, "w")
				FormatTime timestamp, LongDate
				EnvGet username, USERNAME
				ldif_file.WriteLine("# Generated with 'gc' tool - " timestamp " by " username)
				ldif_file.Read(0)
			}
			doit(ldap_conn, ldif_file)
		} else
			throw Exception("Connect: " error(Ldap.Err2String(ldap_conn.GetLastError())))
	} finally {
		if (ldap_conn) {
			ldap_conn.Unbind()
			Ansi.WriteLine("`nConnetion closed")
		}
		if (ldif_file) {
			ldif_file.WriteLine("`n# Process completed")
			ldif_file.Close()
		}
	}
	
	return _log.Exit()
}

doit(ldap_conn, ldif_file = 0) {
	_log := new Logger("app.gc." A_ThisFunc)

	if (_log.Logs(Logger.Input)) {
		_log.Input("ldap_conn", ldap_conn)
	}

	; HINT: Find all groups, which are no 'ibm-nestedGroups': (&(objectclass=groupOfNames)(!(objectclass=ibm-nestedGroup)))
	; Find all groups, which are 'ibm-nestedGroups': (objectclass=ibm-nestedGroup)
	
	Ansi.WriteLine("Searching for groups: (&(objectclass=ibm-nestedGroup)(cn=" G_group_pattern ")) ...", true)
	if (ldap_conn.Search(sr, G_base_dn, "(&(objectclass=ibm-nestedGroup)(cn=" G_group_pattern "))", Ldap.SCOPE_SUBTREE, ["member", "ibm-memberGroup"]) = 0) {
		G_status_groups := ldap_conn.CountEntries(sr)
		Ansi.WriteLine("Found " G_status_groups " group(s)", true)
		if (G_status_groups > 0) {
			Ansi.WriteLine(" ", true)
			entry := ldap_conn.FirstEntry(sr)
			if (entry <> 0) {
				check_entry(ldap_conn, entry)
				while ((entry := ldap_conn.NextEntry(entry)) > 0) {
					G_status_current++
					check_entry(ldap_conn, entry, ldif_file)
				}
				if (entry <> 0)
					throw Exception("NextEntry: " error(Ldap.Err2String(ldap_conn.GetLastError())))
			} else
				throw Exception("FirstEntry: " error(Ldap.Err2String(ldap_conn.GetLastError())))
		}
	} else
		throw Exception("Search: " error(Ldap.Err2String(ldap_conn.GetLastError())))

	return _log.Exit()
}

error(msg) {
	_log := new Logger("app.gc." A_ThisFunc)
	
	if (_log.Logs(Logger.Input)) {
		_log.Input("msg", msg)
	}
	
	if (_log.Logs(Logger.Fatal)) {
		_log.Fatal(msg)
	}

	return _log.Exit(Ansi.ESC "[0;31m" msg Ansi.Reset())
}

check_entry(ldap_conn, entry, ldif_file = 0) {
	_log := new Logger("class." A_ThisFunc)

	if (_log.Logs(Logger.Input)) {
		_log.Input("ldap_conn", ldap_conn)
		_log.Input("entry", entry)
	}
	
	lines := []
	adds := []

	dn := ldap_conn.GetDn(entry)
	Ansi.Write(Ansi.SaveCursorPosition() "Check " dn "... ", true)
	Ansi.Flush()
	attrs := {}
	n := 0
	attr := ldap_conn.FirstAttribute(entry)
	if (attr = 0) {
		Ansi.WriteLine(error("Group has no member attribute"))
		return _log.Exit(-1)
	}
	System.StrCpy(attr, st_attr)
	vals := ldap_conn.GetValues(entry, attr)
	if (vals = 0)
		throw Exception("GetValues: " error(Ldap.Err2String(ldap_conn.GetLastError())))
	vals := System.PtrListToStrArray(vals)
	attrs.Insert(st_attr, vals)
	while ((attr := ldap_conn.NextAttribute(entry)) <> 0) {
		System.StrCpy(attr, st_attr)	
		vals := System.PtrListToStrArray(ldap_conn.GetValues(entry, attr))
		attrs.Insert(st_attr, vals)
	}
	if (attr <> 0)
		throw Exception("NextAttribute: " error(Ldap.Err2String(ldap_conn.GetLastError())))
	ibm_mg_ix := Arrays.Index(attrs["ibm-memberGroup"])
	update_win_status("Checking " dn "[" attrs["member"].MaxIndex() "]")
	for i, v in attrs["member"] {
		if (ldap_conn.Search(sr_member, v, "(objectclass=groupOfNames)") = 0) {
			if (member_n := ldap_conn.CountEntries(sr_member)) {
				if (!ibm_mg_ix.HasKey(v)) {
					n++
					lines.Insert(Ansi.ESC "[34m   -> " v Ansi.Reset())
					if (ldif_file)
						adds.Insert(v)
				}
			} else if (member_n <> 0)
				throw Exception("CountEntries: " error(Ldap.Err2String(ldap_conn.GetLastError())))
		} else
			if (ldap_conn.GetLastError() = 32) {
				if (G_print_search_failures)
					lines.Insert(Ansi.ESC "[31m   -X " v Ansi.Reset())
			} else
				throw Exception("Search: " error(Ldap.Err2String(ldap_conn.GetLastError())))
	}
	update_win_status()

	Ansi.Write(Ansi.RestoreCursorPosition() Ansi.EraseLine())
	if (n = 0)
		process_line("Check " dn "... " Ansi.ESC "[32;7mOK" Ansi.Reset())
	else
		process_line("Check " dn "... " Ansi.ESC "[31;7mFAIL" Ansi.Reset())
	if (lines.MaxIndex()) {
		loop % lines.MaxIndex()
			process_line(lines[A_Index])

		if (ldif_file) {
			ldif_file.WriteLine("")
			ldif_file.WriteLine("dn: " dn)
			ldif_file.WriteLine("changetype: modify")
			ldif_file.WriteLine("add: ibm-memberGroup")
			loop % adds.MaxIndex()
				ldif_file.WriteLine("ibm-memberGroup: " adds[A_Index])
			ldif_file.Read(0)
		}
	}

	return _log.Exit(n)
}

update_win_status(msg = "") {
	pct := Ceil((G_status_current / G_status_groups) * 100) "%"
	WinSetTitle % "gc - " G_status_current " of " G_status_groups " (" pct ")" (msg = "" ? "" : " - " msg)
}

process_line(text = " ") {
	Pager.Write(text, false)
}
