pub const glfw = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "1");
    @cInclude("GLFW/glfw3.h");
});

pub const stbi = @cImport({
    @cInclude("stb_image.h");
});
