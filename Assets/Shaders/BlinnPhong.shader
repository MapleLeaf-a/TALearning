// Upgrade NOTE: replaced '_World2Object' with 'unity_WorldToObject'

Shader "Unlit/BlinnPhong"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Kd("漫反射系数", Color) = (1,1,1)
        _Ks("镜面反射系数", Color) = (1,1,1)
        _Ka("环境光系数", Color) = (1,1,1)
        _KsPow("镜面反射cos幂次", Float) = 200
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        //前向渲染：对每个物体，依次计算每个光源的影响，然后输出最终颜色
        Pass
        {
            //主光源
            Tags { "LightMode" = "ForwardBase" }
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag_base
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            
            

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normal_world : TEXCOORD1;
                float4 pos_world : TEXCOORD2;
            };
            
            sampler2D _MainTex;
            float4 _MainTex_ST;

            float3 _Kd;
            float3 _Ks;
            float3 _Ka;
            float _KsPow;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.normal_world = normalize(mul(v.normal, unity_WorldToObject));
                o.pos_world = mul(unity_ObjectToWorld, v.vertex); //得到顶点的世界坐标
                return o;
            }

            fixed4 frag_base (v2f i) : SV_Target
            {
                fixed3 col = tex2D(_MainTex, i.uv).xyz;

                fixed3 I = _LightColor0;
                float4 light_pos = _WorldSpaceLightPos0;

                float3 normal_world = normalize(i.normal_world);

                float3 l = normalize(light_pos - i.pos_world).xyz; //指向光源的单位向量

                float r = distance(i.pos_world, light_pos);
                float r_square = r * r;

                //漫反射光
                fixed3 Ld = _Kd * col * (I / r_square) * max(0, dot(normal_world, l));

                float3 view_world = normalize(_WorldSpaceCameraPos - i.pos_world.xyz);
                float3 h = normalize(view_world + l);//半程向量

                //镜面反射光
                fixed3 Ls = _Ks * (I / r_square) * pow(max(0, dot(normal_world, h)), _KsPow);

                //环境光
                float3 La = UNITY_LIGHTMODEL_AMBIENT.rgb * col;

                return fixed4(La + Ls + Ld, 1.0);
            }

            ENDCG
        }
        Pass
        {
            //附加光源
            Tags { "LightMode"="ForwardAdd" }

            Blend One One

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag_add
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normal_world : TEXCOORD1;
                float4 pos_world : TEXCOORD2;
            };
            
            sampler2D _MainTex;
            float4 _MainTex_ST;

            float3 _Kd;
            float3 _Ks;
            float3 _Ka;
            float _KsPow;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.normal_world = normalize(mul(v.normal, unity_WorldToObject));
                o.pos_world = mul(unity_ObjectToWorld, v.vertex); //得到顶点的世界坐标
                return o;
            }

            fixed4 frag_add (v2f i) : SV_Target
            {
                fixed3 col = tex2D(_MainTex, i.uv).xyz;

                fixed3 I = _LightColor0;
                float4 light_pos = _WorldSpaceLightPos0;

                float3 normal_world = normalize(i.normal_world);

                float3 l = normalize(light_pos - i.pos_world).xyz; //指向光源的单位向量

                float r = distance(i.pos_world, light_pos);
                float r_square = r * r;

                //漫反射光
                fixed3 Ld = _Kd * col * (I / r_square) * max(0, dot(normal_world, l));

                float3 view_world = normalize(_WorldSpaceCameraPos - i.pos_world.xyz);
                float3 h = normalize(view_world + l);//半程向量

                //镜面反射光
                fixed3 Ls = _Ks * (I / r_square) * pow(max(0, dot(normal_world, h)), _KsPow);

                return fixed4(Ls + Ld, 1.0);
            }

            ENDCG
        }
        Pass
        {
            //阴影投射通道,这个Pass只需要深度信息,不需要任何光照或纹理采样,Unity会自动识别这个LightMode为ShadowCaster的Pass,并在需要生成阴影贴图时调用它
            Tags {"LightMode" = "ShadowCaster"}

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // 关键编译指令：处理不同光源类型（平行光、点光源）的阴影贴图
            #pragma multi_compile_shadowcaster
            /*让 Unity 为这个 Pass 生成多个版本，分别处理不同情况：平行光（正交投影）、点光源（立方体阴影贴图，需要6个面）、聚光灯（透视投影）*/
            #include "UnityCG.cginc"

            // 使用Unity内置的结构和宏来简化代码
            struct v2f {
                V2F_SHADOW_CASTER;
                /*这是一个宏，它会展开成几个从顶点着色器传给片元着色器的变量。
                通常包含：裁剪空间位置、深度偏移后的位置等。
                你不需要关心它具体有什么，你只需要知道它帮你预留了正确传递深度数据所需的“容器”。*/
            };

            v2f vert(appdata_base v)
            {
                v2f o;
                // 这个宏会帮你处理顶点位置到阴影贴图空间的转换
                TRANSFER_SHADOW_CASTER_NORMALOFFSET(o)
                /*这是一个宏，写在顶点着色器末尾。
                它的作用是：把顶点位置转换到阴影贴图空间，并应用一些特殊修正。
                所谓“阴影贴图空间”，就是从光源视角看到的裁剪空间。
                “Normal Offset”是 Unity 的一个优化技巧：沿着法线方向稍微偏移顶点位置，可以缓解阴影贴图的“自遮挡”（Acne）问题。
                你不需要自己算矩阵，这个宏全包了。*/
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                // 这个宏会根据光源类型，输出正确的深度值
                SHADOW_CASTER_FRAGMENT(i)
                /*这是一个宏，写在片元着色器里。
                它的作用是：根据光源类型，输出正确的深度值。
                对于平行光和聚光灯，它输出一个单一的深度值。
                对于点光源，它需要输出到立方体贴图的对应面上。
                你甚至不需要 return 什么，这个宏内部已经处理了 return。*/
            }
            ENDCG
        }
    }
}
