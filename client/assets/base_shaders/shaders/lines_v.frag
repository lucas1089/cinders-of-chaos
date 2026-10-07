precision highp float;
precision highp int;

uniform mat4 modelMatrix;
uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform mat4 viewMatrix;
uniform mat3 normalMatrix;

attribute vec3 position;
attribute vec3 normal;
attribute vec2 uv;

varying vec2 vUv;
varying vec3 vNormal;

attribute highp vec2 a_TexCoord;
attribute highp vec2 a_Vertex;
uniform highp mat3 u_TextureMatrix;
uniform highp mat3 u_TransformMatrix;
uniform highp mat3 u_ProjectionMatrix;
varying highp vec2 v_TexCoord;

highp vec4 calculatePosition() {
    return vec4(u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0), 1.0);
}

void main()
{
    vNormal = position * normal;
    vUv = uv;

    gl_Position = projectionMatrix * vec4( position, 1.0 );
	
}
