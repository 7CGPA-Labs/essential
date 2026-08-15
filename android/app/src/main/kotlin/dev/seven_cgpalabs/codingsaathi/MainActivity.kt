package dev.seven_cgpalabs.codingsaathi

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import dev.seven_cgpalabs.codingsaathi.settings.AppPreferenceActivity

/**
 * MainActivity
 *
 * Primary Native Android entry point launching the CodingSaathi System Settings UI.
 */
class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val intent = Intent(this, AppPreferenceActivity::class.java)
        startActivity(intent)
        finish()
    }
}
