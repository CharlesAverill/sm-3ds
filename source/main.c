// 3DS-specific main file for Super Metroid port
// Based on snesrev/sm with minimal modifications for 3DS

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include "SDL2/SDL.h"
#include <3ds.h>

#include "src/snes/ppu.h"
#include "src/types.h"
#include "src/sm_rtl.h"
#include "src/sm_cpu_infra.h"
#include "src/config.h"
#include "src/util.h"
#include "src/spc_player.h"

enum Button {
  BTN_A = 0,
  BTN_B = 1,
  BTN_SELECT = 2,
  BTN_START = 3,
  BTN_DPAD_R = 4,
  BTN_DPAD_L = 5,
  BTN_DPAD_U = 6,
  BTN_DPAD_D = 7,
  BTN_R = 8,
  BTN_L = 9,
  BTN_X = 10,
  BTN_Y = 11,
  BTN_ZL = 14,
  BTN_ZR = 15,
};

static void SDLCALL AudioCallback(void *userdata, Uint8 *stream, int len);
static void HandleInput(int keyCode, int keyMod, bool pressed);
static void HandleCommand(uint32 j, bool pressed);

bool g_debug_flag;
bool g_is_turbo;
bool g_want_dump_memmap_flags;
bool g_new_ppu = true;
bool g_other_image;
struct SpcPlayer *g_spc_player;

static uint8_t g_pixels[256 * 4 * 240];
static uint8_t g_my_pixels[256 * 4 * 240];

int g_got_mismatch_count;

static const char kWindowTitle[] = "Super Metroid 3DS";
static SDL_Window *g_window;
static SDL_Renderer *g_renderer;
static SDL_Texture *g_texture;

static uint8 g_paused, g_turbo, g_replay_turbo = true;
static uint8 g_gamepad_buttons;
static int g_input1_state;
static bool g_display_perf;
static int g_curr_fps;
static int g_ppu_render_flags = 0;
static int g_snes_width = 256, g_snes_height = 240;
static int g_sdl_audio_mixer_volume = SDL_MIX_MAXVOLUME;

extern Snes *g_snes;

void NORETURN Die(const char *error) {
  fprintf(stderr, "Error: %s\n", error);
  exit(1);
}

void Warning(const char *error) {
  fprintf(stderr, "Warning: %s\n", error);
}

void RtlDrawPpuFrame(uint8 *pixel_buffer, size_t pitch, uint32 render_flags) {
  uint8 *ppu_pixels = g_other_image ? g_my_pixels : g_pixels;
  for (size_t y = 0; y < 240; y++)
    memcpy((uint8_t *)pixel_buffer + y * pitch, ppu_pixels + y * 256 * 4, 256 * 4);
}

static void DrawPpuFrame(void) {
  int render_scale = PpuGetCurrentRenderScale(g_snes->ppu, g_ppu_render_flags);
  uint8 *pixel_buffer = 0;
  int pitch = 0;

  if (SDL_LockTexture(g_texture, NULL, (void **)&pixel_buffer, &pitch) != 0) {
    printf("Failed to lock texture: %s\n", SDL_GetError());
    return;
  }

  RtlDrawPpuFrame(pixel_buffer, pitch, g_ppu_render_flags);

  SDL_UnlockTexture(g_texture);
  SDL_RenderClear(g_renderer);
  SDL_RenderCopy(g_renderer, g_texture, NULL, NULL);
  SDL_RenderPresent(g_renderer);
}

static SDL_mutex *g_audio_mutex;
static uint8 *g_audiobuffer, *g_audiobuffer_cur, *g_audiobuffer_end;
static int g_frames_per_block;
static uint8 g_audio_channels;
static SDL_AudioDeviceID g_audio_device;

void RtlApuLock(void) {
  SDL_LockMutex(g_audio_mutex);
}

void RtlApuUnlock(void) {
  SDL_UnlockMutex(g_audio_mutex);
}

static void SDLCALL AudioCallback(void *userdata, Uint8 *stream, int len) {
  if (SDL_LockMutex(g_audio_mutex)) Die("Mutex lock failed!");
  while (len != 0) {
    if (g_audiobuffer_end - g_audiobuffer_cur == 0) {
      RtlRenderAudio((int16 *)g_audiobuffer, g_frames_per_block, g_audio_channels);
      g_audiobuffer_cur = g_audiobuffer;
      g_audiobuffer_end = g_audiobuffer + g_frames_per_block * g_audio_channels * sizeof(int16);
    }
    int n = IntMin(len, g_audiobuffer_end - g_audiobuffer_cur);
    if (g_sdl_audio_mixer_volume == SDL_MIX_MAXVOLUME) {
      memcpy(stream, g_audiobuffer_cur, n);
    } else {
      SDL_memset(stream, 0, n);
      SDL_MixAudioFormat(stream, g_audiobuffer_cur, AUDIO_S16, n, g_sdl_audio_mixer_volume);
    }
    g_audiobuffer_cur += n;
    stream += n;
    len -= n;
  }
  SDL_UnlockMutex(g_audio_mutex);
}

int idx_of_btn(enum Button b) {
  switch(b) {
    case BTN_DPAD_U:
      return 0;
    case BTN_DPAD_D:
      return 1;
    case BTN_DPAD_L:
      return 2;
    case BTN_DPAD_R:
      return 3;
    case BTN_SELECT:
      return 4;
    case BTN_START:
      return 5;
    case BTN_A:
      return 6;
    case BTN_B:
      return 7;
    case BTN_X:
      return 8;
    case BTN_Y:
      return 9;
    case BTN_L:
      return 10;
    case BTN_R:
      return 11;
  }
}

static void HandleCommand(uint32 j, bool pressed) {
  j = 1 + idx_of_btn(j);
  if (j <= kKeys_Controls_Last) {
    static const uint8 kKbdRemap[] = { 0, 4, 5, 6, 7, 2, 3, 8, 0, 9, 1, 10, 11 };
    if (pressed)
      g_input1_state |= 1 << kKbdRemap[j];
    else
      g_input1_state &= ~(1 << kKbdRemap[j]);
    return;
  }

  if (j == kKeys_Turbo) {
    g_turbo = pressed;
    return;
  }

  if (!pressed)
    return;

  if (j <= kKeys_Load_Last) {
    RtlSaveLoad(kSaveLoad_Load, j - kKeys_Load);
  } else if (j <= kKeys_Save_Last) {
    RtlSaveLoad(kSaveLoad_Save, j - kKeys_Save);
  } else if (j <= kKeys_Replay_Last) {
    RtlSaveLoad(kSaveLoad_Replay, j - kKeys_Replay);
  } else {
    switch (j) {
    case kKeys_Reset: RtlReset(1); break;
    case kKeys_Pause: g_paused = !g_paused; break;
    case kKeys_ReplayTurbo: g_replay_turbo = !g_replay_turbo; break;
    default: break;
    }
  }
}

// #undef main
int main(int argc, char** argv) {
  // Use default config - no config file on 3DS
  ParseConfigFile(NULL);

  g_snes_width = 256;
  g_snes_height = 240;
  g_ppu_render_flags = g_config.extend_y * kPpuRenderFlags_Height240 
                      | g_config.new_renderer * kPpuRenderFlags_NewRenderer; //g_config.new_renderer * kPpuRenderFlags_NewRenderer;

  // Initialize SDL
  if(SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_GAMECONTROLLER | SDL_INIT_JOYSTICK) != 0) {
    printf("Failed to init SDL: %s\n", SDL_GetError());
    return 1;
  }

  SDL_JoystickEventState(SDL_ENABLE);
  SDL_GameControllerEventState(SDL_ENABLE);

  if (SDL_NumJoysticks() > 0) {
      SDL_GameControllerOpen(0);
  }

  Result rc = romfsInit();
  if (rc)
    while(true);

  // Load ROM from romfs
  const char* filename = "romfs:/sm.smc";
  Snes *snes = SnesInit(filename);

  if(snes == NULL) {
    char buf[256];
    snprintf(buf, sizeof(buf), "Unable to load ROM: %s\nMake sure sm.smc is in romfs/", filename);
    Die(buf);
    return 1;
  }

  // Create window - 3DS top screen
  SDL_Window *window = SDL_CreateWindow(
    kWindowTitle,
    SDL_WINDOWPOS_UNDEFINED,
    SDL_WINDOWPOS_UNDEFINED,
    400, 240,
    SDL_WINDOW_SHOWN
  );

  if(window == NULL) {
    printf("Failed to create window: %s\n", SDL_GetError());
    return 1;
  }
  g_window = window;

  // Create renderer - SOFTWARE for 3DS
  g_renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
  if (g_renderer == NULL) {
    printf("Failed to create renderer: %s\n", SDL_GetError());
    return 1;
  }

  // Create texture
  g_texture = SDL_CreateTexture(g_renderer, SDL_PIXELFORMAT_ARGB8888,
                                SDL_TEXTUREACCESS_STREAMING,
                                g_snes_width, g_snes_height);
  if (g_texture == NULL) {
    printf("Failed to create texture: %s\n", SDL_GetError());
    return 1;
  }

  // Setup audio
  g_audio_mutex = SDL_CreateMutex();
  if (!g_audio_mutex) Die("No mutex");

  g_spc_player = SpcPlayer_Create();
  SpcPlayer_Initialize(g_spc_player);

  SDL_AudioSpec want = { 0 }, have;
  want.freq = 44100;
  want.format = AUDIO_S16;
  want.channels = 2;
  want.samples = 2048;
  want.callback = &AudioCallback;
  g_audio_device = SDL_OpenAudioDevice(NULL, 0, &want, &have, 0);
  if (g_audio_device == 0) {
    printf("Failed to open audio device: %s\n", SDL_GetError());
  } else {
    g_audio_channels = 2;
    g_frames_per_block = (534 * have.freq) / 32000;
    g_audiobuffer = (uint8 *)malloc(g_frames_per_block * have.channels * sizeof(int16));
  }

  PpuBeginDrawing(snes->snes_ppu, g_pixels, 256 * 4, 0);
  PpuBeginDrawing(snes->my_ppu, g_my_pixels, 256 * 4, 0);

  RtlReadSram();

  bool running = true;
  uint32 lastTick = SDL_GetTicks();
  uint32 frameCtr = 0;
  uint8 audiopaused = true;

  printf("Super Metroid starting...\n");

  while (running) {
    SDL_Event event;

    while (SDL_PollEvent(&event)) {
      switch (event.type) {
      // case SDL_KEYDOWN:
      //   HandleInput(event.key.keysym.sym, event.key.keysym.mod, true);
      //   break;
      // case SDL_KEYUP:
      //   HandleInput(event.key.keysym.sym, event.key.keysym.mod, false);
      //   break;
      case SDL_JOYBUTTONDOWN:
        HandleCommand(event.jbutton.button, true);
        break;
      case SDL_JOYBUTTONUP:
        HandleCommand(event.jbutton.button, false);
        break;
      case SDL_QUIT:
        running = false;
        break;
      }
    }

    if (g_paused != audiopaused) {
      audiopaused = g_paused;
      if (g_audio_device)
        SDL_PauseAudioDevice(g_audio_device, audiopaused);
    }

    if (g_paused) {
      SDL_Delay(16);
      continue;
    }

    int inputs = g_input1_state | g_gamepad_buttons;
    uint8 is_replay = RtlRunFrame(inputs);

    frameCtr++;
    g_snes->disableRender = (g_turbo ^ (is_replay & g_replay_turbo)) && (frameCtr & 0xf) != 0;

    if (!g_snes->disableRender)
      DrawPpuFrame();

    // Frame delay for 60 fps
    static const uint8 delays[3] = { 17, 17, 16 };
    lastTick += delays[frameCtr % 3];
    uint32 curTick = SDL_GetTicks();

    if (lastTick > curTick) {
      uint32 delta = lastTick - curTick;
      if (delta > 500) {
        lastTick = curTick - 500;
        delta = 500;
      }
      SDL_Delay(delta);
    } else if (curTick - lastTick > 500) {
      lastTick = curTick;
    }
  }

  // Cleanup
  SDL_PauseAudioDevice(g_audio_device, 1);
  SDL_CloseAudioDevice(g_audio_device);
  SDL_DestroyMutex(g_audio_mutex);
  free(g_audiobuffer);
  SDL_DestroyTexture(g_texture);
  SDL_DestroyRenderer(g_renderer);
  SDL_DestroyWindow(window);
  SDL_Quit();

  return 0;
}
