// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump

import de.sgitaize.openminipump.ui.Updates
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdatesTest {
    @Test fun versionOrder() {
        assertTrue(Updates.newer("1.0.1", "1.0.0"))
        assertTrue(Updates.newer("1.0.0", "1.0.0-beta"))
        assertTrue(Updates.newer("1.0.0-beta.2", "1.0.0-beta"))
        assertTrue(Updates.newer("1.1", "1.0.9"))
        assertFalse(Updates.newer("1.0.0-beta", "1.0.0-beta"))
        assertFalse(Updates.newer("1.0.0-beta", "1.0.0"))
        assertFalse(Updates.newer("0.9.0", "1.0.0-beta"))
    }
}
