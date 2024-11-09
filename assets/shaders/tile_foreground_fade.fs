#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

// Output fragment color
out vec4 finalColor;

struct Circle {
    vec2 pos;
    float radius;
};

#define MAX_CIRCLES  128

uniform Circle circles[MAX_CIRCLES];
uniform int numCircles = 0;
uniform float falloff_dist = 20;

void main() {
    vec2 pos = vec2(gl_FragCoord.x, gl_FragCoord.y);
    vec4 color = texture(texture0, fragTexCoord)*fragColor;
    vec4 vAlpha = vec4(1,1,1,1);
    int cCount = min(numCircles, MAX_CIRCLES);
    for (int i = 0; i < cCount; i++) {
        float dist = distance(pos, circles[i].pos);
        if (dist < circles[i].radius) {
            color.a = 0;
            break;
        } else if (dist < circles[i].radius + falloff_dist) {
            float t = smoothstep(falloff_dist, 0, dist - circles[i].radius);
            color.a = clamp(color.a - t, 0, 1);
        }
    }

    finalColor = color;
}