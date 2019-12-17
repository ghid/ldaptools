; ahk: console
; ahk: x86
#NoEnv
#Warn All, StdOut
SetBatchLines -1

#Include <testcase-libs>
#Include <Ldap>

class GroupInfoTest extends TestCase {

	requires() {
		return [TestCase, GroupInfo]
	}

	static SERVER := "localhost"
	static PORT := 10389
	static COVER_SERVICE := false
	static output := A_TEMP "\gi-test.txt"
	static figures := A_ScriptDir "\figures\gi"

	@BeforeClass_Setup() {
		RC_OK := -1
	    RC_MISSING_ARG := -2
	    RC_INVALID_ARGS := -3
		RC_CYCLE_DETECTED := -4
		RC_CN_NOT_FOUND := -5
		RC_CN_AMBIGOUS := -6
		RC_TOO_MANY_ARGS := -8

		G_LDAP_CONN := 0
		Ansi.NO_BUFFER := true
	}

	; ahklint-ignore-begin: W002
	@BeforeClass_CheckLDAPServer() {
		for ldapService in ComObjGet("winmgmts:")
				.execQuery("Select * from Win32_Service where Name='apacheds-default'") {
			if (ldapService.state != "Running") {
				TestCase.writeLine("Starting apacheds-default service...")
				GroupInfoTest.COVER_SERVICE := true
				if ((returnCode := ldapService.startService()) != 0) {
					this.fail("*** FATAL: apacheds-default service could not be startet: " returnCode
							,, true)
				}
				maxTries := 600
				while (maxTries > 0 && ldapService.state != "Running") {
					sleep 100
					for ldapService in ComObjGet("winmgmts:")
							.execQuery("Select * from Win32_Service where Name='apacheds-default'") {
						break
					}
					maxTries--
				}
				if (maxTries == 0) {
					this.fail("*** FATAL: apacheds-default service could not be startet in an adequate time"
							,, true)
				} else {
					TestCase.writeLine("apacheds-default service has been started")
				}
			} else {
				TestCase.writeLine("apacheds-default service is already running")
			}
			break
		}
	}

	@AfterClass_TearDown() {
		if (GroupInfoTest.COVER_SERVICE) {
			for ldapService in ComObjGet("winmgmts:")
					.execQuery("Select * from Win32_Service where Name='apacheds-default'") {
				if (ldapService.state = "Running") {
					TestCase.writeLine("Stopping apacheds-default service...")
					if ((returnCode := ldapService.stopService()) != 0) {
						this.fail("*** FATAL: apacheds-default service could not be stopped: " returnCode
								,, true)
					}
					maxTries := 600
					while (maxTries > 0 && ldapService.state != "Stopped") {
						sleep 100
						for ldapService in ComObjGet("winmgmts:")
								.execQuery("Select * from Win32_Service where Name='apacheds-default'") {
							break
						}
						maxTries--
					}
					if (maxTries = 0) {
						this.fail("*** FATAL: apacheds-default service could not be stopped in an adequate time"
								,, true)
					} else {
						TestCase.writeLine("apacheds-default service has been stopped")
					}
				} else {
					TestCase.writeLine("apacheds-default service has already been stopped")
				}
				break
			}
		}
	}
	; ahklint-ignore-end

	@Before_redirStdOut() {
		Ansi.stdOut := FileOpen(A_Temp "\gi-test.txt", "w `n")
	}

	@After_redirStdOut() {
		Ansi.stdOut.close()
		Ansi.stdOut := Ansi.__initStdOut()
		FileDelete %A_Temp%\gi-test.txt
	}

	@Before_ResetOpts() {
		GroupInfo.options := GroupInfo.setDefaults()
		EnvSet GI_OPTIONS,
	}

	@Test_evaluateCommandLineOptions() {
		this.assertException(GroupInfo, "evaluateCommandLineOptions",,, [])
		this.assertException(GroupInfo, "evaluateCommandLineOptions"
				,,, ["one", "two", "three"])
		GroupInfo.options := GroupInfo.setDefaults()
		GroupInfo.Options.output := true
		GroupInfo.Options.append := true
		this.assertException(GroupInfo, "evaluateCommandLineOptions",,
				, ["xxx"])
		GroupInfo.options := GroupInfo.setDefaults()
		GroupInfo.Options.lower := true
		GroupInfo.Options.upper := true
		this.assertException(GroupInfo, "evaluateCommandLineOptions",,
				, ["xxx"])
		GroupInfo.options := GroupInfo.setDefaults()
		GroupInfo.Options.ibmAllGroups := true
		GroupInfo.Options.ibmNestedGroups := true
		this.assertException(GroupInfo, "evaluateCommandLineOptions",,
				, ["xxx"])
	}

	@Test_usage() {
		this.assertEquals(GroupInfo.run(["--help"]), "")
		this.assertEquals(TestCase.fileContent(GroupInfoTest
				.figures "\usage.txt")
				, TestCase.fileContent(GroupInfoTest.output))
	}

	@Test_simple() {
		this.assertEquals(GroupInfo.run(["-p", "10389", "snoopy"]), 3)
		this.assertEquals(TestCase.fileContent(GroupInfoTest
				.figures "\simple.txt")
				, TestCase.fileContent(GroupInfoTest.output))
	}

	@Test_simpleUpperCase() {
		this.assertEquals(GroupInfo.run(["-p", "10389", "-u", "snoopy"]), 3)
		this.assertEquals(TestCase.fileContent(GroupInfoTest
				.figures "\simpleUpperCase.txt")
				, TestCase.fileContent(GroupInfoTest.output))
	}

	@Test_short() {
		this.assertEquals(GroupInfo.run(["-p", "10389", "-1", "snoopy"]), 3)
		this.assertEquals(TestCase.fileContent(GroupInfoTest.output)
				, TestCase.fileContent(GroupInfoTest.figures "\short.txt"))
	}

	@Test_count() {
		this.assertEquals(GroupInfo.run(["-p", "10389", "-c", "snoopy"]), 3)
		this.assertEquals(TestCase.fileContent(GroupInfoTest.output)
				, TestCase.fileContent(GroupInfoTest.figures "\count.txt"))
	}

	@Test_withRefs() {
		this.assertEquals(GroupInfo.run(["-p", "10389", "-r", "snoopy"]), 3)
		this.assertEquals(TestCase.fileContent(GroupInfoTest.output)
				, TestCase.fileContent(GroupInfoTest.figures "\withRefs.txt"))
	}

	@Test_shortWithRefs() {
		this.assertEquals(GroupInfo.run(["-p", "10389", "-r1", "snoopy"]), 3)
		this.assertEquals(TestCase.fileContent(GroupInfoTest.output)
				, TestCase.fileContent(GroupInfoTest.figures
				. "\shortWithRefs.txt"))
	}

	@Test_withRefsNoColor() {
		this.assertEquals(GroupInfo.run(["-p", "10389", "-r", "--no-color"
				, "snoopy"]), 3)
		this.assertEquals(TestCase.fileContent(GroupInfoTest.output)
				, TestCase.fileContent(GroupInfoTest.figures
				. "\withRefsNoColor.txt"))
	}

	@Test_search() {
		this.assertEquals(GroupInfo.run(["-p", "10389", "-1i", "snoopy"
				, "*own*"]), 2)
		this.assertEquals(TestCase.fileContent(GroupInfoTest.output)
				, TestCase.fileContent(GroupInfoTest.figures "\search.txt"))
	}

	@Test_searchRegEx() {
		this.assertEquals(GroupInfo.run(["-p", "10389", "-1e", "snoopy"
				, "\ws$"]), 2)
		this.assertEquals(TestCase.fileContent(GroupInfoTest.output)
				, TestCase.fileContent(GroupInfoTest.figures
				. "\searchRegEx.txt"))
	}

	@Test_resultOnly() {
		this.assertEquals(GroupInfo.run(["-p", "10389", "-1R", "snoopy"]), 3)
		this.assertEquals(TestCase.fileContent(GroupInfoTest.output)
				, TestCase.fileContent(GroupInfoTest.figures
				. "\resultOnly.txt"))
	}

	@Test_resultOnlySorted() {
		this.assertEquals(GroupInfo.run(["-p", "10389", "-1R", "--sort"
				, "snoopy"]), 3)
		this.assertEquals(TestCase.fileContent(GroupInfoTest.output)
				, TestCase.fileContent(GroupInfoTest.figures
				. "\resultOnlySorted.txt"))
	}

	@Test_printGroups() {
		this.assertEquals(GroupInfo.run(["-p", "10389", "-g", "2", "-g", "1"
				, "snoopy", "(The\s)+([\w']+)"]), 2)
		this.assertEquals(TestCase.fileContent(GroupInfoTest.output)
				, TestCase.fileContent(GroupInfoTest.figures
				. "\printGroups.txt"))
	}
}

exitapp GroupInfoTest.runTests()

#Include %A_ScriptDir%\..\gi.ahk
