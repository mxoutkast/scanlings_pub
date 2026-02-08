package com.scanlings.camera

import androidx.core.content.FileProvider

/**
 * Separate FileProvider to avoid manifest merge conflicts with Godot's built-in provider.
 */
class ScanlingsFileProvider : FileProvider()
