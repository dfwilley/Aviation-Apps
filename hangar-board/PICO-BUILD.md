# Building the Hangar Board with a Raspberry Pi Pico W

Step-by-step instructions for putting together the hangar status board using a Raspberry Pi Pico W and a 7.5 inch e-paper display.

> **Status:** the Pico W firmware (version 1.2) compiles cleanly but has not yet been run on a real board. Notes marked *"not yet confirmed"* below are the places most likely to need a correction after the first real build.

## What you need

| Part | Notes |
|---|---|
| **Raspberry Pi Pico W** with header pins | Must be the **W** model (it has a silver metal can at one end for Wi-Fi). The pre-soldered version is sold as "Pico WH". The plain Pico, Pico 2 and Pico 2 W will not work. |
| **7.5 inch e-paper display**, 800 x 480 | Either of the two options below. |
| **Micro-USB data cable** | Some cables only charge. If the PC never sees the Pico, try another cable. |
| **USB power** for the finished board | Any phone charger or USB port. |
| Windows PC | Only for loading the firmware once. |
| Phone | For the Wi-Fi setup. |

Pick one display option:

- **Option A, no wires:** Waveshare "7.5inch e-Paper Module (B) for Raspberry Pi Pico" (black, white and red). The kit includes the display, a blue "Pico-ePaper-Driver-Board", a ribbon extension and standoffs.
- **Option B, eight jumper wires:** a bare 7.5 inch panel (for example the black-and-white Waveshare 7.5" V2, label `075BN-T7`) plus a Good Display **DESPI-C02** adapter board and eight female-to-female jumper wires.

## Step 1. Load the firmware onto the Pico W

Do this first, before connecting the display.

1. Download the firmware file `hangarboard-picow.uf2`:
   <https://dfwilley.github.io/Aviation-Apps/hangar-board/firmware/hangarboard-picow.uf2>
   (It is also linked from the install page at <https://dfwilley.github.io/Aviation-Apps/hangar-board/>.)
2. Hold down the white **BOOTSEL** button on the Pico.
3. While holding it, plug the Pico into the PC with the USB cable. Then let go.
4. A new drive named **RPI-RP2** appears in File Explorer, like a USB stick.
5. Drag `hangarboard-picow.uf2` onto that drive.
6. The drive disappears by itself after a few seconds. That means it worked, and the Pico has restarted with Hangar Board on it.
7. Unplug the Pico.

To load a newer version later, repeat these steps. Your settings and Wi-Fi password are kept.

## Step 2. Connect the display

Always connect or disconnect the display with the Pico **unplugged**.

The ribbon cable connectors are delicate. Flip up the small latch, slide the ribbon in fully and squarely, then press the latch down. Never pull on a ribbon while the latch is closed.

### Option A: Waveshare Pico kit

1. Plug the display's ribbon into the blue driver board (use the ribbon extension if you want the board further from the display).
2. Check the two small switches on the driver board. Leave **Display Config** as it shipped. Set **Interface Config** to the **4-line SPI** position.
3. Press the Pico W's header pins into the sockets on the driver board. Match the end of the Pico that has the USB connector to the **USB** marking printed on the driver board, so it is not plugged in backwards.

### Option B: DESPI-C02 adapter and jumper wires

1. Plug the display's ribbon into the DESPI-C02.
2. Leave the small switch on the DESPI-C02 at **0.47**.
3. Connect eight jumper wires:

| DESPI-C02 pin | Pico W pin name | Physical pin number |
|---|---|---|
| 3.3V | 3V3 OUT | 36 |
| GND | GND | 18 |
| SDI | GP11 | 15 |
| SCK | GP10 | 14 |
| CS | GP9 | 12 |
| D/C | GP8 | 11 |
| RES | GP12 | 16 |
| BUSY | GP13 | 17 |

Physical pin 1 is next to the USB connector, on the left when the USB connector points up and you are looking at the top of the board. Pins count down the left side to 20, then up the right side from 21 to 40.

Use **3V3 OUT (pin 36)** for power. Do not use VBUS or VSYS, which carry 5 volts.

## Step 3. Set up Wi-Fi

1. Power the Pico from USB.
2. The screen may stay blank or look scrambled at this point. That is normal: the firmware assumes the red Good Display panel until you tell it otherwise in Step 4. If it does show a "Wi-Fi setup" screen, follow the same steps.
3. On your phone, open Wi-Fi settings and join the network **HangarBoard-Setup**. It has no password. Give it up to half a minute to appear after power-up, because the Pico looks for nearby networks first.
4. A setup page should open by itself. If it doesn't, open a browser and go to `192.168.42.1` (*not yet confirmed on a real board*; the correct address is also printed on the e-paper screen when the display type is right).
5. Pick your Wi-Fi network from the list, or type its name. Enter the password and tap **Save and connect**.
6. The Pico restarts and joins your network. Your phone drops back to its normal Wi-Fi.

The password stays on the Pico and is never sent anywhere else. The Pico W only works on 2.4 GHz Wi-Fi, which nearly every router provides.

## Step 4. Choose the display

1. On a phone or computer on the **same Wi-Fi network**, open <http://hangarboard.local>.
   If that doesn't open, find the Pico's address in your router's list of connected devices (it shows up as `hangarboard`) and type that address in.
2. Scroll to **Display and wiring** and set:

| Your display | E-paper display | How it's wired |
|---|---|---|
| Option A, Waveshare Pico kit (red) | Waveshare 7.5 inch (B) V2 (black, white, red) | Waveshare Pico e-Paper module |
| Option B, black-and-white Waveshare panel on a DESPI-C02 | Waveshare 7.5 inch V2 (black and white) | Adapter board (such as DESPI-C02) |

3. Tap **Save**. The Pico restarts, and within about a minute the screen draws the weather. Red panels take 15 to 25 seconds to redraw and flash while they do it.

If the red Waveshare panel shows a wrong or washed-out picture, change **E-paper display** to "Good Display GDEY075Z08 (black, white, red)" and save again. Which of the two this panel needs is *not yet confirmed*.

## Step 5. Set up the board

Everything else is on the same settings page:

- **Board:** airport (default KTUS), tail number, time zone, how often it updates, and the density altitude warning level.
- **Load from maintenance database:** pick `Maintenance Record_be.accdb` and tap **Use these items**. The file is only read, never changed.
- **Aircraft Hobbs time:** enter it after each flight.
- **Due items:** add aircraft or pilot items by date, by Hobbs hours, or whichever comes first.
- **Note:** a free-text line shown on the board.

Then mount the board in the hangar and power it from any USB charger. It reconnects to Wi-Fi and refreshes by itself.

## If something goes wrong

| What you see | What to try |
|---|---|
| No RPI-RP2 drive appears | Hold BOOTSEL *before* plugging in. Try a different USB cable; many are charge-only. |
| No "HangarBoard-Setup" network | Wait 30 seconds after power-up. Unplug and replug. If it still never appears, reload the firmware (Step 1). |
| Setup page doesn't open | Stay joined to HangarBoard-Setup, turn off mobile data for a moment, and browse to `192.168.42.1`. |
| Screen returns to Wi-Fi setup after saving | The password was wrong or the network is out of range. Join HangarBoard-Setup and enter it again. |
| Hangar Wi-Fi was down, board shows the setup screen | Leave it alone. It offers setup for 3 minutes, then retries the saved network, and keeps doing that until the Wi-Fi is back. |
| `hangarboard.local` doesn't open | Use the address from your router's device list. The address is also printed at the bottom of the e-paper screen once it is drawing. |
| Screen blank or scrambled after Step 4 | Check the display and wiring choices. Check the ribbon is fully seated and latched. For Option B, recheck each wire against the table. |
| "Weather unavailable" on the screen | The board is on Wi-Fi but can't reach the internet, or the airport code is wrong. |
| Want to move it to a different Wi-Fi | Settings page, **Wi-Fi**, **Reset Wi-Fi**. Then repeat Step 3. |

## Good to know

- Weather comes from the National Weather Service Aviation Weather Center and is for situational awareness only. Always get an official briefing before flight.
- Anyone on the same Wi-Fi network can open the settings page. It has no password.
- Black-and-white panels mark out-of-limits items with a ⚠ symbol instead of red.
