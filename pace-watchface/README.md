# Pace: watch face for the Garmin Forerunner 165

A layered analog face: a rotating outer seconds ring, a minute ring, rounded outline hands,
a digital time pill, a battery gauge, a date tile and a small seconds dial. When you lower
your wrist it switches to a dim always-on face.

Open `preview.html` in a browser to see it.

## Install it on your watch

This is a one-off setup. Everything is free. Allow about 15 minutes the first time.

### 1. Install the tools on your computer (Windows or Mac)

1. Install **Visual Studio Code**: https://code.visualstudio.com
2. Install the **Connect IQ SDK Manager**: https://developer.garmin.com/connect-iq/sdk/
   - Open it and sign in with your Garmin account.
   - Under **SDK**, download the latest SDK and click **Use as Current SDK**.
   - Under **Devices**, find **Forerunner 165** and download it. If you have the Music
     version, download **Forerunner 165 Music** too.
3. In VS Code, open Extensions (Ctrl+Shift+X, or Cmd+Shift+X on a Mac), search for
   **Monkey C** (by Garmin) and install it.
4. In VS Code press Ctrl+Shift+P (Cmd+Shift+P on a Mac), run
   **Monkey C: Generate a Developer Key** and save the key anywhere. It's only used to
   sign your build.

### 2. Try it in the simulator (optional, but recommended)

1. In VS Code: **File → Open Folder…** and choose this `pace-watchface` folder.
2. Open `source/PaceView.mc`, then **Run → Run Without Debugging** (Ctrl+F5).
3. Pick **Forerunner 165**. The simulator opens with the face running.
   - Use **Settings → Low Power Mode** in the simulator to see the always-on face.

### 3. Build the file for your watch

1. Ctrl+Shift+P → **Monkey C: Build for Device**.
2. Choose **fr165** (or **fr165m** for the Music version) and a folder to save to.
3. You'll get a file called **`pace-watchface.prg`** (the name follows the folder).

### 4. Copy it to the watch

1. Plug the watch into your computer with its USB cable.
   - **Windows:** it shows up in File Explorer as a device called *Forerunner 165*.
   - **Mac:** Macs can't open it directly. Install **OpenMTP** (https://openmtp.ganeshrvel.com),
     a free file-transfer app, and use it to see the watch.
2. Open **`GARMIN` → `APPS`** on the watch and copy the `.prg` file into it.
3. Unplug the watch. It takes a few seconds to install the face.

### 5. Turn it on

On the watch: hold **UP** (Menu) → **Watch Face** → scroll to **Pace** → **Apply**.
You can also press and hold the watch face screen to get to the same menu.

### Change the colours

Open **Garmin Connect** on your phone → your watch → **Watch Faces** → **Pace** →
**Settings** → **Colours**. Sideloaded faces don't always show settings in Connect. If yours
doesn't, change the default in `resources/settings/properties.xml` (0 to 3) and rebuild.

## If the build fails

Copy the error text from VS Code's **Problems** or **Output** panel and paste it to Claude.
This code was written without access to Garmin's compiler, so a small fix may be needed.

## Limits of a Garmin watch face

- While you're looking at the watch, the face redraws **once a second**. With your wrist
  down it redraws once a minute. So the outer ring steps one notch per second instead of
  gliding like the browser preview.
- In always-on mode, the face shifts by a couple of pixels each minute to protect the
  AMOLED screen from burn-in.
