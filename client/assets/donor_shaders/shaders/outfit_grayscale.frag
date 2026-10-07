uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;

vec4 grayscale(vec4 color)
{
  float alphaThreshold = 0.5;

  if (color.a < alphaThreshold) {
    return color;
  }
  
  float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
  return vec4(gray, gray, gray, color.a);
}

void main()
{
  gl_FragColor = grayscale(texture2D(u_Tex0, v_TexCoord));
}
