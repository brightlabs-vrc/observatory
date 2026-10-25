// Copyright 2026 Ayase Minori and Umamusume Racing Society
// Licensed under the BSD-3-Clause License
// See LICENSE for details
//
// In memoriam of Liaku, thank you for bringing warmth for everyone in the URS <3
Shader "Skybox/LiaSky"
{
    Properties
    {
        // Editor-preview values. The names must differ from the Udon globals: a material
        // property shadows a global of the same name. The globals win whenever they are set.
        _SunDirection ("Editor Preview Sun Dir", Vector) = (0, 1, 0, 0)
        _WeatherIntensity ("Editor Preview Weather", Range(0, 1)) = 0
    }
    SubShader
    {
        Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" }
        Cull Off ZWrite Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.5
            #pragma exclude_renderers d3d11_9x gles

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 viewDir : TEXCOORD0;
                // Everything below depends only on globals, so it is constant across the
                // whole skybox draw. Flat interpolation keeps it out of the per-pixel cost.
                nointerpolation float3 sunDir : TEXCOORD1;
                nointerpolation float4 skyParams : TEXCOORD2;
                nointerpolation float sunset : TEXCOORD3;
                nointerpolation float3 sunTint : TEXCOORD4;
                nointerpolation float3 cloudTint : TEXCOORD5;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            float4 _UdonSunDirection;
            float _UdonWeatherIntensity;
            float4 _SunDirection;
            float _WeatherIntensity;

            static const float3 kMemorialDir = float3(0.17609f, 0.44023f, -0.88046f);

            float3 Hash33(float3 p)
            {
                p = frac(p * float3(0.1031f, 0.1030f, 0.0973f));
                p += dot(p, p.yxz + 33.33f);
                return frac((p.xxy + p.yxx) * p.zyx);
            }

            float Hash12(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * 0.1031f);
                p3 += dot(p3, p3.yzx + 33.33f);
                return frac((p3.x + p3.y) * p3.z);
            }

            // One cell of value noise: the four corner hashes are what keep adjacent cells
            // continuous, so this cannot be reduced to a per-cell hash.
            float ValueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                f = f * f * (3.0f - 2.0f * f);
                float a = Hash12(i);
                float b = Hash12(i + float2(1.0f, 0.0f));
                float c = Hash12(i + float2(0.0f, 1.0f));
                float d = Hash12(i + float2(1.0f, 1.0f));
                return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
            }

            static const float kCloudScale = 1.8f;

            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.vertex = UnityObjectToClipPos(v.vertex);
                o.viewDir = v.vertex.xyz;

                // A zero-length global means no Udon data yet. Fall back to the preview
                // sliders so the shader previews in the editor and never normalizes zero.
                bool preview = dot(_UdonSunDirection.xyz, _UdonSunDirection.xyz) < 1e-6f;
                float3 sunRaw = preview ? _SunDirection.xyz : _UdonSunDirection.xyz;
                if (dot(sunRaw, sunRaw) < 1e-6f)
                {
                    sunRaw = float3(0.0f, 1.0f, 0.0f);
                }
                float weather = saturate(preview ? _WeatherIntensity : _UdonWeatherIntensity);
                float3 sunDir = normalize(sunRaw);

                float isNight = 1.0f - smoothstep(-0.2f, 0.2f, sunDir.y);
                float sunset = 1.0f - smoothstep(0.0f, 0.55f, abs(sunDir.y));
                float starMask = 1.0f - smoothstep(-0.22f, -0.03f, sunDir.y);
                float sunVisible = smoothstep(-0.08f, 0.02f, sunDir.y);
                float skyVisibility = lerp(1.0f, 0.08f, weather);
                float3 sunWarm = lerp(float3(1.0f, 0.96f, 0.88f), float3(1.0f, 0.48f, 0.18f), sunset);
                float3 sunColor = lerp(sunWarm, float3(0.4f, 0.4f, 0.4f), weather);

                o.sunDir = sunDir;
                // x: night mask, y: star gain (sun-elevation gated), z: weather, w: storm-night scale.
                o.skyParams = float4(isNight, starMask * skyVisibility, weather, 1.0f - 0.5f * weather);
                o.sunset = sunset;
                o.sunTint = sunColor * lerp(1.0f, 0.25f, weather) * sunVisible;
                // Clouds are lit by the same sun: bright cumulus, grey overcast, warm at
                // sunset, and dim blue-grey at night so the deck still reads against the
                // star field.
                half3 cloudDay = lerp(half3(0.90f, 0.93f, 0.97f),
                                      half3(0.34f, 0.36f, 0.39f), (half)weather);
                cloudDay = lerp(cloudDay, half3(1.0f, 0.55f, 0.28f), (half)(sunset * 0.55f));
                o.cloudTint = (float3)lerp(cloudDay, half3(0.030f, 0.035f, 0.050f), (half)starMask);
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float3 viewDir = normalize(i.viewDir);
                float isNight = i.skyParams.x;
                float weather = i.skyParams.z;

                half t = saturate(viewDir.y * 0.5f + 0.5f);
                half3 daySkyColor = lerp(half3(0.075f, 0.2f, 0.35f), half3(0.15f, 0.4f, 0.7f), t);
                half3 color = lerp(lerp(daySkyColor, half3(0.25f, 0.27f, 0.3f), (half)weather),
                                   half3(0.002f, 0.002f, 0.006f) * (half)i.skyParams.w,
                                   (half)isNight);

                // The band is view-dependent (horizon height and sun azimuth); the amount is flat, so
                // this branch is coherent and absent away from sunrise/sunset.
                UNITY_BRANCH
                if (i.sunset > 0.001f)
                {
                    float band = 1.0f - smoothstep(0.0f, 0.35f, viewDir.y);
                    float toward = saturate(dot(viewDir, i.sunDir));
                    float glow = i.sunset * band * (0.25f + 0.75f * toward);
                    color = lerp(color, half3(1.0f, 0.42f, 0.16f), (half)glow);
                }

                // isNight and skyParams.y are uniform across the draw, so the branches are
                // coherent.
                UNITY_BRANCH
                if (isNight < 1.0f)
                {
                    // Squared chord distance: 2 * (1 - dot). The thresholds are the exact
                    // dot-space edges converted, so the disk and corona profiles are kept.
                    float sunDist2 = 2.0f - 2.0f * dot(viewDir, i.sunDir);
                    float disk = 1.0f - smoothstep(0.0004f, 0.0008f, sunDist2);
                    float corona = (1.0f - smoothstep(0.01f, 0.2f, sunDist2)) * 0.4f;
                    color += (half)(disk + corona) * (half3)i.sunTint;
                }

                UNITY_BRANCH
                if (i.skyParams.y > 0.0f)
                {
                    float3 starGrid = viewDir * 150.0f;
                    float3 gridId = floor(starGrid);
                    float3 h = Hash33(gridId);
                    float starProbability = h.x;
                    // Independent channels keep the centres spread across the cell; deriving
                    // all three from one scalar would place them on a line.
                    float3 starCenter = frac(h.yzx * float3(1.13f, 1.31f, 1.71f)) * 0.6f + 0.2f;

                    float spread = frac(starProbability * 124.45f);
                    float sizeFactor = spread * 0.12f + 0.03f;
                    float stars = 1.0f - smoothstep(0.0f, sizeFactor, length(frac(starGrid) - starCenter));
                    stars *= step(0.35f, starProbability);

                    float twinkleSpeed = 2.0f + spread * 3.0f;
                    stars *= sin(_Time.y * twinkleSpeed + starProbability * 6.2831f) * 0.14f + 0.86f;
                    color += (half)stars * half3(0.85f, 0.92f, 1.0f) * (half)i.skyParams.y;

                    // Dedicated Golden Memorial Star (LiaStar Alignment)
                    float memorialDist2 = 2.0f - 2.0f * dot(viewDir, kMemorialDir);
                    float memorialCore = 1.0f - smoothstep(0.0f, 0.0018f * 0.0018f, memorialDist2);
                    float memorialBloom = (1.0f - smoothstep(0.0f, 0.04f * 0.04f, memorialDist2)) * 0.4f;
                    float memorialPulse = sin(_Time.y * 1.2f) * 0.08f + 0.92f;
                    color += (half)(memorialCore + memorialBloom) * half3(1.0f, 0.85f, 0.45f)
                             * (half)(memorialPulse * 2.2f * i.skyParams.y);
                }

                // A weather-driven deck composited last: the lerp attenuates the sun, stars,
                // and memorial star by (1 - density), exactly as an opaque layer would.
                UNITY_BRANCH
                if (weather > 0.001f && viewDir.y > 0.0f)
                {
                    // Flat-deck projection: clouds grow overhead and compress at the horizon.
                    float2 uv = viewDir.xz / max(viewDir.y, 0.001f) * kCloudScale;
                    float2 wind = float2(0.012f, 0.004f) * _Time.y;
                    float n = ValueNoise(uv + wind);
#ifndef SHADER_API_MOBILE
                    n = n * 0.65f + ValueNoise(uv * 2.17f - wind * 1.6f) * 0.35f;
#endif
                    // weather is coverage: clear at 0, broken near 0.5, overcast at 1.
                    float density = saturate((n - (1.0f - weather)) * 3.0f + weather * 0.45f);
                    density *= smoothstep(0.02f, 0.15f, viewDir.y);

                    half3 litCloud = (half3)i.cloudTint * (half)(0.75f + 0.25f * density);
                    color = lerp(color, litCloud, (half)density);
                }

                return float4((float3)color, 1.0f);
            }
            ENDCG
        }
    }
}
