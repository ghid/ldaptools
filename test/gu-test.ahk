; ahk: console
; ahk: x86
#NoEnv
#Warn All, StdOut
SetBatchLines -1

#Include <testcase-libs>
#Include <Ldap>

class GroupUserTest extends TestCase {

	requires() {
		return [TestCase, GroupUser]
	}

	static SERVER := "localhost"
	static PORT := 10389
	static COVER_SERVICE := false
	static output := A_TEMP "\gu-test.txt"
	static figures := A_ScriptDir "\figures\gu"

	@BeforeClass_Setup() {
		RC_OK := -1
	    RC_MISSING_ARG := -2
	    RC_INVALID_ARGS := -3
		RC_CYCLE_DETECTED := -4
		RC_CN_NOT_FOUND := -5
		RC_CN_AMBIGOUS := -6
		RC_TOO_MANY_ARGS := -7

		G_LDAP_CONN := 0
		Ansi.NO_BUFFER := true
	}

	; ahklint-ignore-begin: W002
	@BeforeClass_CheckLDAPServer() {
		for ldapService in ComObjGet("winmgmts:")
				.execQuery("Select * from Win32_Service where Name='apacheds-default'") {
			if (ldapService.state != "Running") {
				TestCase.writeLine("Starting apacheds-default service...")
				GroupUserTest.COVER_SERVICE := true
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
		if (GroupUserTest.COVER_SERVICE) {
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
		Ansi.stdOut := FileOpen(A_Temp "\gu-test.txt", "w `n")
	}

	@After_redirStdOut() {
		Ansi.stdOut.close()
		Ansi.stdOut := Ansi.__initStdOut()
		FileDelete %A_Temp%\gu-test.txt
	}

	@Before_ResetOpts() {
		GroupUser.options := GroupUser.setDefaults()
		EnvSet GU_OPTIONS,
	}

	@Test_evaluateCommandLineOptions() {
		this.assertException(GroupUser, "evaluateCommandLineOptions",,, [])
		GroupUser.options := GroupUser.setDefaults()
		GroupUser.Options.output := true
		GroupUser.Options.append := true
		this.assertException(GroupUser, "evaluateCommandLineOptions",,
				, ["xxx"])
		GroupUser.options := GroupUser.setDefaults()
		GroupUser.Options.lower := true
		GroupUser.Options.upper := true
		this.assertException(GroupUser, "evaluateCommandLineOptions",,
				, ["xxx"])
	}

	@Test_usage() {
		this.assertEquals(GroupUser.run(["--help"]), "")
		this.assertEquals(TestCase.fileContent(GroupUserTest
				.figures "\usage.txt")
				, TestCase.fileContent(GroupUserTest.output))
	}

	@Test_simple() {
		this.assertEquals(GroupUser.run(["-p", "10389", "Peanuts"]), 7)
		this.assertEquals(TestCase.fileContent(GroupUserTest
				.figures "\simple.txt")
				, TestCase.fileContent(GroupUserTest.output))
	}

	@Test_simpleUpperCase() {
		this.assertEquals(GroupUser.run(["-p", "10389", "-u", "Peanuts"]), 7)
		this.assertEquals(TestCase.fileContent(GroupUserTest
				.figures "\simpleUpperCase.txt")
				, TestCase.fileContent(GroupUserTest.output))
	}

	@Test_short() {
		this.assertEquals(GroupUser.run(["-p", "10389", "-1", "Peanuts"]), 7)
		this.assertEquals(TestCase.fileContent(GroupUserTest.output)
				, TestCase.fileContent(GroupUserTest.figures "\short.txt"))
	}

	@Test_count() {
		this.assertEquals(GroupUser.run(["-p", "10389", "-c", "Peanuts"]), 7)
		this.assertEquals(TestCase.fileContent(GroupUserTest.output)
				, TestCase.fileContent(GroupUserTest.figures "\count.txt"))
	}

	@Test_withRefs() {
		this.assertEquals(GroupUser.run(["-p", "10389", "-r", "Peanuts"]), 7)
		this.assertEquals(TestCase.fileContent(GroupUserTest.output)
				, TestCase.fileContent(GroupUserTest.figures "\withRefs.txt"))
	}

	@Test_shortWithRefs() {
		this.assertEquals(GroupUser.run(["-p", "10389", "-r1", "Peanuts"]), 7)
		this.assertEquals(TestCase.fileContent(GroupUserTest.output)
				, TestCase.fileContent(GroupUserTest.figures
				. "\shortWithRefs.txt"))
	}

	@Test_withRefsNoColor() {
		this.assertEquals(GroupUser.run(["-p", "10389", "-r", "--no-color"
				, "Peanuts"]), 7)
		this.assertEquals(TestCase.fileContent(GroupUserTest.output)
				, TestCase.fileContent(GroupUserTest.figures
				. "\withRefsNoColor.txt"))
	}

	@Test_resultOnly() {
		this.assertEquals(GroupUser.run(["-p", "10389", "-1R", "Peanuts"]), 7)
		this.assertEquals(TestCase.fileContent(GroupUserTest.output)
				, TestCase.fileContent(GroupUserTest.figures
				. "\resultOnly.txt"))
	}

	@Test_resultOnlySorted() {
		this.assertEquals(GroupUser.run(["-p", "10389", "-1R", "--sort"
				, "Peanuts"]), 7)
		this.assertEquals(TestCase.fileContent(GroupUserTest.output)
				, TestCase.fileContent(GroupUserTest.figures
				. "\resultOnlySorted.txt"))
	}
}

exitapp GroupUserTest.runTests()

#Include %A_ScriptDir%\..\gu.ahk
