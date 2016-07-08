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

	global G_help, G_version, G_ldap_server := "localhost", G_ldap_port := 389, G_base_dn, G_ldap_port, G_print_search_failure := false, G_print_oc_missing := false, G_print_entry_missing := false, G_print_unnecessary_oc := false, G_print_all := false, G_pager := true, G_ldif, G_group_pattern := "*", G_promote := true, G_ignore_groups_filter := ""

	global G_status_groups := 0, G_status_current := 0

	rc := 0
	
	op := new OptParser("gc [options] [<ldap-server> [<group-name-pattern>]]",, "GC_OPTIONS")
	op.Add(new OptParser.String("p", "port", G_ldap_port, "port-num", "Port number of the LDAP server (default=" G_ldap_port ")",, G_ldap_port, G_ldap_port))
	op.Add(new OptParser.String("b", "base-dn", G_base_dn, "base-dn", "Provide a base dn to start the search"))
	op.Add(new OptParser.String(0, "ldif", G_ldif, "filename", "Generate an LDIF file to add missing ibm-memberGroup entries", OptParser.Opt_ARG, G_ldif, G_ldif))
	op.Add(new OptParser.Boolean(0, "promote", G_promote, "Add ibm-memberGroups class to all matching groups if missing", OptParser.OPT_NEG | OptParser.OPT_NEG_USAGE, G_promote))
	op.Add(new OptParser.String(0, "ignore-group", G_ignore_groups_filter, "group-name-pattern", "Ignore groups matching this filter (may be used multiple)", OptParser.OPT_ARG | OptParser.OPT_MULTIPLE))
	op.Add(new OptParser.Boolean(0, "pager", G_pager, "Enable paging (default: on)", OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE, G_pager, G_pager))
	op.Add(new OptParser.Boolean(0, "print-search-failure", G_print_search_failure, "Print if a search failed (default: off)", OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE))
	op.Add(new OptParser.Boolean(0, "print-oc-missing", G_print_oc_missing, "Print if objectclass ibm-nestedGroup is missing (default: off)", OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE))
	op.Add(new OptParser.Boolean(0, "print-entry-missing", G_print_entry_missing, "Print if an ibm-nestedGroup entry is missing", OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE))
	op.Add(new OptParser.Boolean(0, "print-unnecessary-oc", G_print_unnecessary_oc, "Print if objectclass ibm-nestedGroup is implemented but not used", OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE))
	op.Add(new OptParser.Boolean(0, "print-all", G_print_all, "Print all messages exept --print-search-failure"))
	op.Add(new OptParser.Boolean(0, "env", _env, "Use/ignore environment variable GC_OPTIONS", OptParser.OPT_NEG|OptParser.OPT_NEG_USAGE))
	op.Add(new OptParser.Boolean(0, "version", G_version, "Print version info"))
	op.Add(new OptParser.Boolean("h", "help", G_help, "Print help"))


	try {
		args := op.Parse(System.vArgs)

		OptParser.TrimArg(G_ldap_port)
		OptParser.TrimArg(G_base_dn)
		OptParser.TrimArg(G_ldif)
		OptParser.TrimArg(G_ignore_groups_filter)

		if (_init.Logs(Logger.Finest)) {
			_init.Finest("G_ldap_port", G_ldap_port)
			_init.Finest("G_base_dn", G_base_dn)
			_init.Finest("G_ldif", G_ldif)
			_init.Finest("G_promote", G_promote)
			_init.Finest("G_ignore_groups_filter", G_ignore_groups_filter)
			_init.Finest("G_pager", G_pager)
			_init.Finest("G_print_search_failure", G_print_search_failure)
			_init.Finest("G_print_oc_missing", G_print_oc_missing)
			_init.Finest("G_print_entry_missing", G_print_entry_missing)
			_init.Finest("G_print_unnecessary_oc", G_print_unnecessary_oc)
			_init.Finest("G_print_all", G_print_all)
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

		if (G_print_all) {
			G_print_oc_missing := true
			G_print_entry_missing := true
			G_print_unnecessary_oc := true
		}

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
	fails := 0

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
			fails := doit(ldap_conn, ldif_file)
		} else
			throw Exception("Connect: " error(Ldap.Err2String(ldap_conn.GetLastError())))
	} finally {
		if (ldap_conn) {
			ldap_conn.Unbind()
			Ansi.WriteLine("`nConnetion closed - " fails " group(s) affected")
		}
		if (ldif_file) {
			ldif_file.WriteLine("`n# Process completed - " fails " group(s) affected")
			ldif_file.Close()
		}
	}
	
	return _log.Exit(fails)
}

doit(ldap_conn, ldif_file = 0) {
	_log := new Logger("app.gc." A_ThisFunc)

	if (_log.Logs(Logger.Input)) {
		_log.Input("ldap_conn", ldap_conn)
		_log.Input("ldif_file", ldif_file)
	}

	fails := 0

	; HINT: Find all groups, which are no 'ibm-nestedGroups': (&(objectclass=groupOfNames)(!(objectclass=ibm-nestedGroup)))
	; Find all groups, which are 'ibm-nestedGroups': (objectclass=ibm-nestedGroup)

	filter := build_filter()

	Ansi.WriteLine("Searching for groups:`n" highlight_filter(filter) "`nin " (G_base_dn <> "" ? G_base_dn : "whole directory") " ...", true)
	if (G_ldif) {
		ldif_filter := "`nLDAP filter applied:`n" highlight_filter(filter, false)
		ldif_filter := StrReplace(ldif_filter, "`n", "`n# ")
		ldif_file.WriteLine(ldif_filter)
		ldif_file.WriteLine("`n# Base DN: " (G_base_dn <> "" ? G_base_dn : "Complete directory"))
		ldif_file.Read(0)
	}

	if (ldap_conn.Search(sr, G_base_dn, filter, Ldap.SCOPE_SUBTREE, ["objectclass", "member", "ibm-memberGroup"]) = 0) {
		G_status_groups := ldap_conn.CountEntries(sr)
		Ansi.WriteLine("Found " G_status_groups " group(s)", true)
		if (G_status_groups > 0) {
			Ansi.WriteLine(" ", true)
			entry := ldap_conn.FirstEntry(sr)
			if (entry <> 0) {
				fails += check_entry(ldap_conn, entry, ldif_file)
				while ((entry := ldap_conn.NextEntry(entry)) > 0) {
					G_status_current++
					fails += check_entry(ldap_conn, entry, ldif_file)
				}
				if (entry <> 0)
					throw Exception("NextEntry: " error(Ldap.Err2String(ldap_conn.GetLastError())))
			} else
				throw Exception("FirstEntry: " error(Ldap.Err2String(ldap_conn.GetLastError())))
		}
	} else
		throw Exception("Search: " error(Ldap.Err2String(ldap_conn.GetLastError())))

	return _log.Exit(fails)
}

highlight_filter(filter, syntax_highlighting = true) {

	static OPERATOR  := "[0;32m"
		 , ATTRIBUTE := "[0;35m"
		 , VALUE     := "[0;34m"
		 , COMPARE   := "[0;31m"
		 , RESET     := "[0m"

	string := ""
	indent := 0
	i := 1
	while (i <= StrLen(filter)) {
		char := SubStr(filter, i, 1)
		st := SubStr(filter, i-1, 2)
		if (RegExMatch(st, "\([|&!]", $)) {
			indent++
			string .= char indent_text("", indent)
		} else if (st = ")(") {
			string .= indent_text(char, indent)
		} else if (st = "))") {
			indent--
			string .= indent_text(char, indent)
		} else {
			string .= char
		}
		i++
	}
	if (indent < 0)
		throw Exception("Invalid LDAP filter")

	filter := string

	if (syntax_highlighting) {
		filter := RegExReplace(filter, "(\w*?)=([\w_-]+)", ATTRIBUTE "${1}=" VALUE "${2}" RESET)
		filter := RegExReplace(filter, "[&|!]", OPERATOR "${0}" RESET)
		filter := RegExReplace(filter, "[<>~*=]", COMPARE "${0}" RESET)
	}

	return filter
}

indent_text(text, num) {
	return ("`n" "  ".Repeat(num) text)
}

build_filter() {
	_log := new Logger("app.gc." A_ThisFunc)
	
	if (_log.Logs(Logger.Finest)) {
		_log.Finest("G_group_pattern", G_group_pattern)
		_log.Finest("G_ignore_groups_filter", G_ignore_groups_filter)
	}

	filter := "(objectclass=ibm-nestedGroup)"
	if (G_promote)
		filter := "(|" filter "(&(objectclass=groupOfNames)(!(objectclass=ibm-nestedGroup))))"
	if (G_group_pattern)
		filter := "(&" filter "(cn=" G_group_pattern "))"
	if (G_ignore_groups_filter) {
		filter := "(&" filter 
		loop parse, G_ignore_groups_filter, `n
			filter .= "(!(cn=" A_LoopField "))"
		filter .= ")"
	}

	return _log.Exit(filter)
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
		_log.Input("ldif_file", ldif_file)
	}
	
	lines := []
	adds := []
	ocs := []
	no_ocs := []

	dn := ldap_conn.GetDn(entry)
	Ansi.Write(Ansi.SaveCursorPosition() "Check " dn "... ", true)
	Ansi.Flush()
	attrs := {}
	fail := false
	attr := ldap_conn.FirstAttribute(entry)
	if (attr = 0) {
		Ansi.WriteLine(error("Group has no member attribute"))
		return _log.Exit(-1)
	}
	System.StrCpy(attr, st_attr)
	vals := ldap_conn.GetValues(entry, attr)
	if (vals = 0)
		throw Exception("GetValues: " error(Ldap.Err2String(ldap_conn.GetLastError())))
	vals := System.PtrListToStrArray(vals, false)
	attrs.Insert(st_attr, vals)
	while ((attr := ldap_conn.NextAttribute(entry)) <> 0) {
		System.StrCpy(attr, st_attr)	
		vals := System.PtrListToStrArray(ldap_conn.GetValues(entry, attr), false)
		attrs.Insert(st_attr, vals)
	}
	if (attr <> 0)
		throw Exception("NextAttribute: " error(Ldap.Err2String(ldap_conn.GetLastError())))
	ibm_mg_ix := Arrays.Index(attrs["ibm-memberGroup"])
	update_win_status("Checking " dn "[" attrs["member"].MaxIndex() "]")

	contains_groups := 0
	for i, v in attrs["member"] {
		if (ldap_conn.Search(sr_member, v, "(objectclass=groupOfNames)") = 0) {
			if (member_n := ldap_conn.CountEntries(sr_member)) {
				contains_groups++
				if (!ibm_mg_ix.HasKey(v)) {
					if (G_print_entry_missing)
						lines.Insert(Ansi.ESC "[34m   -> ibm-memberGroup entry mssing for " v Ansi.Reset())
					if (ldif_file)
						adds.Insert(v)
					fail := true
				}
			} else if (member_n <> 0)
				throw Exception("CountEntries: " error(Ldap.Err2String(ldap_conn.GetLastError())))
		} else
			if (ldap_conn.GetLastError() = 32) {
				if (G_print_search_failure)
					lines.Insert(Ansi.ESC "[31m   -> Member not found " v Ansi.Reset())
			} else
				throw Exception("Search: " error(Ldap.Err2String(ldap_conn.GetLastError())))
		if (!mod(A_Index, 1000))
			update_win_status("Checking " dn "[" A_Index " of " attrs["member"].MaxIndex() "]")
	}
	update_win_status()

	if (!contains_groups && Arrays.Index(attrs["objectclass"]).HasKey("ibm-nestedGroup")) {
		if (G_print_unnecessary_oc)
			lines.Insert(Ansi.ESC "[35m   -> Unnecessary objectclass ibm-nestedGroup" Ansi.Reset())
		no_ocs.Insert("ibm-nestedGroup")
		fail := true
	} else if (contains_groups && !Arrays.Index(attrs["objectclass"]).HasKey("ibm-nestedGroup")) {
		if (G_print_oc_missing)
			lines.Insert(Ansi.ESC "[33m   -> ibm-nestedGroup objectclass missing" Ansi.Reset())
		ocs.Insert("ibm-nestedGroup")
		fail := true
	}

	Ansi.Write(Ansi.RestoreCursorPosition() Ansi.EraseLine())
	if (!fail)
		process_line("Check " dn "... " Ansi.ESC "[32;7mOK" Ansi.Reset())
	else
		process_line("Check " dn "... " Ansi.ESC "[31;7mFAIL" Ansi.Reset())

	if (fail) {
		loop % lines.MaxIndex()
			process_line(lines[A_Index])

		if (ldif_file) {
			ldif_file.WriteLine("")
			ldif_file.WriteLine("dn: " dn)
			ldif_file.WriteLine("changetype: modify")
			if (no_ocs.MaxIndex()) {
				ldif_file.WriteLine("delete: objectclass")
				loop % no_ocs.MaxIndex()
					ldif_file.WriteLine("objectclass: " no_ocs[A_Index])
			} else {
				if (ocs.MaxIndex()) {
					ldif_file.WriteLine("add: objectclass")
					loop % ocs.MaxIndex()
						ldif_file.WriteLine("objectclass: " ocs[A_Index])
				}
				if (adds.MaxIndex()) {
					if (ocs.MaxIndex())
						ldif_file.WriteLine("-")
					ldif_file.WriteLine("add: ibm-memberGroup")
					loop % adds.MaxIndex()
						ldif_file.WriteLine("ibm-memberGroup: " adds[A_Index])
				}
			}
			ldif_file.Read(0)
		}
	}

	return _log.Exit(fail)
}

update_win_status(msg = "") {
	pct := Ceil((G_status_current / G_status_groups) * 100) "%"
	WinSetTitle % "gc - " G_status_current " of " G_status_groups " (" pct ")" (msg = "" ? "" : " - " msg)
}

process_line(text = " ") {
	Pager.Write(text, false)
}
