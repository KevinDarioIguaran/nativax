/*
    stb implementation TU — compiled once (image decode/write, truetype).
*/
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#include "stb_image.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"
