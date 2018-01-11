; ahk: x86
#NoEnv
SetBatchLines -1
; #Warn All, OutputDebug

#Include <logging>
#Include <testcase>
#Include <string>
#Include <ansi>
#Include <ldap>

class gi_Test extends TestCase {

	static SERVER := "localhost"
		 , PORT := 10389
		 , COVER_SERVICE := false

	@BeforeClass_Setup() {
		RC_OK             := -1
	    RC_MISSING_ARG    := -2
	    RC_INVALID_ARGS   := -3
		RC_CYCLE_DETECTED := -4
		RC_CN_NOT_FOUND   := -5
		RC_CN_AMBIGOUS    := -6

		G_LDAP_CONN := 0
	}

	@BeforeClass_CheckLDAPServer() {
		for ldap_svc in ComObjGet("winmgmts:").ExecQuery("Select * from Win32_Service where Name='apacheds-default'") {
			if (ldap_svc.State <> "Running") {
				OutputDebug Starting apacheds-default service...
				gi_test.COVER_SERVICE := true	
				if ((ldap_rc := ldap_svc.StartService()) <> 0)
					this.Fail("*** FATAL: apacheds-default service could not be startet: " ldap_rc,, true)
				max_tries := 600
				while (max_tries > 0 && ldap_svc.State <> "Running") {
					sleep 100
					for ldap_svc in ComObjGet("winmgmts:").ExecQuery("Select * from Win32_Service where Name='apacheds-default'")
						break
					max_tries--
				}
				if (max_tries = 0)
					this.Fail("*** FATAL: apacheds-default service could not be startet in an adequate time",, true)
				else
					OutputDebug apacheds-default service has been started
			} else
				OutputDebug apacheds-default service is already running
			break
		}
	}

	@AfterClass_TearDown() {
		if (gi_test.COVER_SERVICE) {
			for ldap_svc in ComObjGet("winmgmts:").ExecQuery("Select * from Win32_Service where Name='apacheds-default'") {
				if (ldap_svc.State = "Running") {
					OutputDebug Stopping apacheds-default service...
					if ((ldap_rc := ldap_svc.StopService()) <> 0)
						this.Fail("*** FATAL: apacheds-default service could not be stopped: " ldap_rc,, true)
					max_tries := 600
					while (max_tries > 0 && ldap_svc.State <> "Stopped") {
						sleep 100
						for ldap_svc in ComObjGet("winmgmts:").ExecQuery("Select * from Win32_Service where Name='apacheds-default'")
							break
						max_tries--
					}
					if (max_tries = 0)
						this.Fail("*** FATAL: apacheds-default service could not be stopped in an adequate time",, true)
					else
						OutputDebug apacheds-default service has been stopped
				} else
					OutputDebug apacheds-default service has already been stopped
				break
			}
		}
	}

	; @Test_CheckLdapData() {
	; 	ld := new Ldap(gi_test.SERVER, gi_test.PORT)	
	; 	ld.Connect()
	; 	ld.Search("cn=peanuts,dc=example,dc=com"
	; 	ld.Unbind()
	; }

	@Before_ResetOpts() {
		G_append := ""
		G_base_dn := ""
		G_cn := ""
		G_color := -1
		G_count := 0
		G_count_only := 0
		G_filter := "*"
		G_group := 0
		G_group_list := []
		G_groupfilter := "groupOfNames"
		G_help  := 0
		G_host := gi_test.SERVER
		G_ibm_all_groups := 0
		G_ibm_nested_group := 0
		G_ignore_case := -1
		G_lower := 0
		G_max_nested_lv := 32
		G_out_h := 0
		G_output := ""
		G_port := gi_test.PORT
		G_quiet := 1
		G_refs := 0
		G_regex := 0
		G_result_only := 1
		G_short := 0
		G_sort := 0
		G_upper := 0
		G_version := 0

		G_member_list := []
		G_scanned_group := []
		G_out_file_name := ""
		G_group_list := []
	}

	@Test_Case1() {
		G_cn := "Linus van Pelt"
		this.AssertEquals(main(), 2)
	}
}

exitapp gi_Test.RunTests()

#Include %A_ScriptDir%\..\gi.ahk
