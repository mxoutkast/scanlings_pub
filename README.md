# Scanlings

**Scan real-world objects. Summon unique creatures. Master the ladder.**

Scanlings is a camera-driven creature collection game that transforms everyday objects into collectible, battle-ready companions. Combining cutting-edge GenAI with deep auto-battler mechanics, Scanlings emphasizes "Virtual Vinyl" aesthetics and Supercell-style competitive clarity.

## Core Loop

1.  **Scan:** Use your camera to capture any real-world object.
2.  **Summon:** GenAI analyzes the object's attributes to generate a unique creature within the **Sacred 8 Archetypes**.
3.  **Battle:** Compete in turn-based, server-simulated auto-battles on the **Ghost Ladder**.
4.  **Fuse:** Evolve your creatures by scanning a second object, unlocking new passives and rarity tiers.

## Getting Started

To experience the full GenAI creature generation, you need both the Android client and a running instance of the backend server.

### 1. Setup the Backend

The GenAI pipeline (Gemini/Lucy) and battle logic reside in the `/backend` folder.

* Navigate to `/backend`.
* Configure your `.env` file with your Gemini and Decart API keys.
* Run the server locally or deploy it to a service like Render.
* **Note:** Ensure your server is accessible via a public URL (or local IP if on the same network) so the mobile client can communicate with it.

### 2. Install the Client

You can either build the Godot project from the `/client` folder or use a pre-built binary:

* **Download the APK:** Grab the latest build from our [Releases page](https://github.com/mxoutkast/scanlings_pub/releases).
* **Point to Server:** Upon first launch, enter your Backend URL in the app settings to enable scanning and summoning.

## Technical Stack

*   **Client:** Godot 4.2 LTS (Android-first)
*   **Backend:** TypeScript / Node.js (Hosted on Render)
*   **Intelligence:** Gemeini 2.5-flash-lite (Vision & Logic), Decart Lucy Image Edit (Visual Identity)

## Project Structure

*   `client/`: Godot project source code and assets.
*   `backend/`: TypeScript server handling GenAI pipelines and battle simulation.
*   `android_plugin_src/`: Custom Godot Android plugin for advanced camera functionality.

## Status

Active development. Backend logic for scan/fuse pipelines and battle simulation is established. Godot client implementation for Android is in progress.
