pub const glfw = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
});

pub const stb = @cImport({
    @cInclude("stb_truetype.h");
    @cInclude("stb_image.h");
});
