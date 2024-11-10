#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

// Output fragment color
out vec4 finalColor;

void main()
{
    vec2 texSize = textureSize(texture0, 0);
    float r = 10;
    float rr = r * r;
    float count = 0;
    vec4 texelColor = vec4(0, 0, 0, 0);
    vec2 topLeft = gl_FragCoord.xy - vec2(r, r);
    vec2 botright = gl_FragCoord.xy + vec2(r, r);

    for (float x = 0; x < r * 2; x += 1) {
        for (float y = 0; y < r * 2; y += 1) {
            float xx = x * x;
            float yy = y * y;
            if (xx + yy <= rr) {
                vec2 px = gl_FragCoord.xy + vec2(x, y);
                vec2 p = px / texSize;
                texelColor += texture(texture0, p);
                count += 1;
            }
        }
    }
    texelColor /= count;

    // final color is the color from the texture 
    //    times the tint color (colDiffuse)
    //    times the fragment color (interpolated vertex color)
    finalColor = texelColor*colDiffuse*fragColor;
}