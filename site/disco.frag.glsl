#version 300 es
// Ported from DiscoShaderSource in ../DiscoOverlay.m. Keep the native lighting,
// mirror-cell grid, beam geometry, and deployment curve in sync with that source.
precision highp float;
uniform vec4 canvas;
uniform vec4 viewport;
uniform vec4 timing;
uniform vec2 resolution;
out vec4 fragColor;
float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
float beamField(vec2 q, float rotation, float radius) {
  float energy=0.0;
  const float longitudeCells=56.0;
  const float longitudeDensity=longitudeCells/(2.0*3.14159265359);
  for (int i=0;i<48;i++) {
    float fi=float(i);
    float latitudeCell=mod(fi*11.0+3.0,31.0)-15.0;
    float longitudeCell=mod(fi*17.0+5.0,longitudeCells);
    float latitude=(latitudeCell+0.5)/10.0;
    float longitude=(longitudeCell+0.5)/longitudeDensity-rotation;
    float latitudeRadius=cos(latitude);
    vec3 facetNormal=vec3(sin(longitude)*latitudeRadius,sin(latitude),cos(longitude)*latitudeRadius);
    vec3 sourceDirection=normalize(vec3(-0.60,-0.70,1.0));
    vec3 reflected=reflect(-sourceDirection,facetNormal);
    float projectedLength=length(reflected.xy);
    if (projectedLength<0.04) continue;
    vec2 beamDirection=reflected.xy/projectedLength;
    vec2 origin=facetNormal.xy*radius*0.82;
    vec2 local=q-origin;
    float along=dot(local,beamDirection);
    if (along<=0.0) continue;
    float across=abs(local.x*beamDirection.y-local.y*beamDirection.x);
    float divergence=0.012+hash21(vec2(fi,9.0))*0.028;
    float halfWidth=0.0015+max(0.0,along-radius)*divergence;
    float core=1.0-smoothstep(halfWidth*0.10,halfWidth*0.36,across);
    float body=1.0-smoothstep(halfWidth*0.30,halfWidth,across);
    float haze=(1.0-smoothstep(halfWidth*0.75,halfWidth*2.6,across))*0.10;
    float start=smoothstep(radius*0.95,radius*2.6,along);
    float brightness=0.22+0.70*pow(hash21(vec2(fi,13.0)),1.7);
    float illumination=smoothstep(0.02,0.55,dot(facetNormal,sourceDirection));
    float visibleFacet=smoothstep(-0.10,0.28,facetNormal.z);
    float directionality=smoothstep(0.10,0.72,projectedLength);
    float visibility=illumination*visibleFacet*directionality;
    float volume=(core*0.40+body*0.22+haze)/(1.0+along*0.50);
    energy+=volume*start*brightness*visibility;
  }
  return 1.0-exp(-energy*1.55);
}
void main() {
  vec2 canvasPosition=viewport.xy+vec2(gl_FragCoord.x / resolution.x, 1.0 - gl_FragCoord.y / resolution.y)*viewport.zw;
  vec2 uv=canvasPosition/canvas.xy; float aspect=canvas.x/max(canvas.y,1.0);
  float t=timing.x; float drop=timing.y;
  float spring=exp(-4.2*drop)*(cos(9.5*drop)+0.442105*sin(9.5*drop));
  float fall=1.0-spring*(1.0-smoothstep(0.70,0.95,drop));
  float lamp=smoothstep(1.0,1.12,drop); float radius=0.027;
  float ballY=mix(-radius*1.8,0.10,fall);
  float rotation=t*0.30;
  vec2 p=vec2((uv.x-0.5)*aspect,uv.y); vec2 center=vec2(0,ballY); vec2 q=p-center;
  bool ballPass=canvas.w>0.5;
  float light=ballPass ? 0.0 : beamField(q,rotation,radius)*lamp;
  float dimAlpha=ballPass ? 0.0 : 0.78*lamp;
  vec3 color=vec3(light);
  float alpha=dimAlpha+light*(1.0-dimAlpha);
  float pixel=canvas.z;
  if (ballPass) {
    float stringEnd=ballY-radius*0.95;
    float stringMask=(1.0-smoothstep(pixel*0.55,pixel*1.6,abs(p.x))) * step(0.0,uv.y) * step(uv.y,stringEnd);
    color=mix(color,vec3(0.58),stringMask*0.85); alpha=mix(alpha,1.0,stringMask*0.85);
    float rr=dot(q,q)/(radius*radius);
    if (rr < 1.0) {
    vec2 nxy=q/radius; float z=sqrt(max(0.0,1.0-rr));
    const float longitudeCells=56.0;
    const float longitudeDensity=longitudeCells/(2.0*3.14159265359);
    float lon=atan(nxy.x,z)+rotation; float lat=asin(nxy.y);
    vec2 grid=vec2(lon*longitudeDensity,lat*10.0); vec2 cell=floor(grid); vec2 edge=abs(fract(grid)-0.5);
    float wrappedCell=mod(mod(cell.x,longitudeCells)+longitudeCells,longitudeCells);
    float seam=smoothstep(0.43,0.49,max(edge.x,edge.y)); float facet=hash21(vec2(wrappedCell,cell.y));
    float flon=(cell.x+0.5)/longitudeDensity-rotation; float facetLatitude=(cell.y+0.5)/10.0;
    vec3 fn=normalize(vec3(sin(flon)*cos(facetLatitude),sin(facetLatitude),cos(flon)*cos(facetLatitude)));
    vec3 key=normalize(vec3(-0.6,-0.7,1.0)); vec3 fill=normalize(vec3(0.85,0.15,0.6));
    float diffuse=0.15+0.38*max(0.0,dot(fn,key));
    float spec=pow(max(0.0,dot(fn,key)),72.0)*1.8+pow(max(0.0,dot(fn,fill)),110.0);
    float reflection=pow(0.5+0.5*sin(flon*7.0+facetLatitude*4.0+facet*2.0),5.0);
    float rim=pow(1.0-z,2.2); float silver=diffuse+reflection*0.32+spec+rim*0.25;
    vec3 ball=vec3(clamp(silver,0.0,1.0))*(1.0-seam*0.65);
    float coverage=1.0-smoothstep(radius-pixel,radius,length(q));
      color=mix(color,ball,coverage); alpha=mix(alpha,1.0,coverage);
    }
  }
  fragColor=vec4(color,alpha);
}
