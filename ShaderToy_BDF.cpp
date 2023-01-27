/***************************************************************************
 # Copyright (c) 2015-22, NVIDIA CORPORATION. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/
#include "ShaderToy_BDF.h"

#include "dear_imgui/imgui.h"

#if FALCOR_D3D12_AVAILABLE
FALCOR_EXPORT_D3D12_AGILITY_SDK
#endif

namespace {
    const char* kSceneStr = "SCENE";
    const char* kTraceStr = "TRACE";
    const char* kShadowStr = "SHADOW";

    Gui::RadioButtonGroup kColoringRBs = { {0,"Default",true},{1,"Stepsize",true},{2,"Shadow stepsize",true},{3,"Original Segment Tracing",true}};
    enum class Coloring : uint32_t { DEFAULT = 0, STEPSIZE = 1, SHADOWSTEP = 2, SEGMENT_TRACING = 3};

    Gui::RadioButtonGroup kColorStepFunRBs = { {0,"Old",true},{1,"HSV",true},{2,"2",true},{3,"3",true},{4,"4",true} };

    Gui::RadioButtonGroup kSceneRBs = { {0,"Blobs", true}, {1,"Primitives", true},
        {2,"Sphere", true}, {3,"Box", true}, {4,"Cylinder", true}, {5,"Torus", true}, {6,"Test", true} };
    enum class Scenes : uint32_t {BLOBS = 0, PRIMITIVES = 1, SPHERE = 2, BOX = 3, CYLINDER = 4, TORUS = 5,TEST = 6};

    Gui::RadioButtonGroup kTraceRBs = { {0,"sdf_trace", true}, {1,"bdf_trace", true},{2,"segment_trace",true},{3,"their_sphere_trace",true} };
    enum class Tracers : uint32_t {SDF_TRACE = 0, BDF_TRACE = 1, SEGMENT_TRACE = 2, THEIR_SPHERE_TRACE = 3};
    Gui::RadioButtonGroup kShadowRBs = { {0,"sdf_trace", true}, {1,"bdf_trace", true}, {2,"no_shadow",true}};
    enum class Shadows : uint32_t { SDF_TRACE = 0, BDF_TRACE = 1, NO_SHADOW = 2 };
}

void ShaderToy_BDF::onGuiRender(Gui* pGui)
{
    Gui::Window w(pGui, "Falcor", { 485, 600 });
    gpFramework->renderGlobalUI(pGui);
    auto camearGroup = Gui::Group(pGui, "Camera Controls", false);
    if (camearGroup.open())
    {
        if (camearGroup.button("Reset camera")) {
            mpCamera->setPosition(float3(2, 1.25, 1.5));
            mpCamera->setTarget(float3(0, 0, 0));
        }
        mpCamera->renderUI(w);

        camearGroup.release();
    }
    auto settingsGroup = Gui::Group(pGui, "Settings", true);
    if (settingsGroup.open())
    {
        static bool changed = true;

        // Image COLORING

        static Coloring colorID = Coloring::DEFAULT;
        settingsGroup.text("Image:");
        ImGui::PushID("Image:");
        bool changedColoring = settingsGroup.radioButtons(kColoringRBs, reinterpret_cast<uint32_t&>(colorID));
        ImGui::PopID();
        changed |= changedColoring;

        static uint32_t vColoringStepFunID = 4;
        static float3 vColorA = float3( 93,  127, 232 ) / 255.f;
        static float3 vColorB = float3( 92,  236, 220 ) / 255.f;
        static float3 vColorC = float3( 241, 222, 100 ) / 255.f;
        static float3 vColorD = float3( 220, 94,  75  ) / 255.f;
        if (colorID == Coloring::STEPSIZE || colorID == Coloring::SHADOWSTEP)
        {
            settingsGroup.text("Step coloring:");
            changed |= settingsGroup.radioButtons(kColorStepFunRBs, vColoringStepFunID);
            if (vColoringStepFunID >= 2)
            {
                changed |= ImGui::ColorEdit3("Color A", &vColorA.x);
                changed |= ImGui::ColorEdit3("Color B", &vColorB.x);
            }
            if (vColoringStepFunID >= 3)
            {
                changed |= ImGui::ColorEdit3("Color C", &vColorC.x);
            }
            if (vColoringStepFunID == 4)
            {
                changed |= ImGui::ColorEdit3("Color D", &vColorD.x);
            }
        }

        static Scenes sceneID = Scenes::PRIMITIVES, prevSceneID = sceneID;
        static float sThreshold = .5f;
        static float sBlobRadius = 4.f;
        static float3 pPrimitiveData = float3(1);
        static float3 pTestPos = float3(0);
        static int3 pRepeatNum = int3(1000, 0, 1000);
        static float3 pRepeatDist = float3(4);
        static bool pShowPlane = true;
        static Tracers traceID = Tracers::SDF_TRACE;
        static int primaryMaxIter = 512;
        static float primaryMaxDist = 500.0f;
        static float sMarchEpsilon = 0.1f;
        static float sKappaFactor = 2.f;
        static Shadows shadowID = Shadows::SDF_TRACE;
        static int secondaryMaxIter = 256;
        static float secondaryMaxDist = 100.0f;
        static float secondaryEpsilon = 0.001f;
        static float secondaryMinDist = 0.01f;
        static float secondaryNOffset = 0.01f;

        if (colorID != Coloring::SEGMENT_TRACING)
        {
            // SCENE

            settingsGroup.text("Scene:");
            ImGui::PushID("Scene:");
            bool changedScene = settingsGroup.radioButtons(kSceneRBs, reinterpret_cast<uint32_t&>(sceneID));
            ImGui::PopID();
            changed |= changedScene;
            switch (sceneID)
            {
            case Scenes::BLOBS:
                changed |= ImGui::SliderFloat("S_THRESHOLD", &sThreshold, 0.f, 1.f);
                changed |= ImGui::SliderFloat("S_BLOB_RADIUS", &sBlobRadius, 0.f, 8.f);
                if (changedScene)
                {
                    primaryMaxIter = 150;
                    primaryMaxDist = 60.f;
                    shadowID = Shadows::NO_SHADOW;
                    mpCamera->setPosition(float3(0, 3.5, 7));
                    mpCamera->setTarget(float3(0,2.2,0));
                }
                break;
            case Scenes::PRIMITIVES:
                if (changedScene)
                {
                    mpCamera->setPosition(float3(6, 3, 4));
                    mpCamera->setTarget(float3(0,0,0.5));
                    if (traceID == Tracers::THEIR_SPHERE_TRACE)
                        traceID = Tracers::SDF_TRACE;
                    if (traceID == Tracers::SEGMENT_TRACE)
                        traceID = Tracers::BDF_TRACE;
                }
                break;
            case Scenes::SPHERE:
                changed |= ImGui::SliderFloat("Radius", &pPrimitiveData.y, 0.f, 8.f);
                if (changedScene)
                {
                    pPrimitiveData.y = 0.7f;
                    mpCamera->setPosition(float3(2.f, 1.25f, 1.5f));
                    mpCamera->setTarget(float3(0, 0, 0));
                }
                break;
            case Scenes::BOX:
                changed |= ImGui::SliderFloat3("Size", &pPrimitiveData.x, 0.f, 8.f);
                if (changedScene)
                {
                    pPrimitiveData = float3(0.4f, 0.5f, 0.6f);
                    mpCamera->setPosition(float3(2, 1.25, 1.5));
                    mpCamera->setTarget(float3(0, 0, 0));
                }
                break;
            case Scenes::CYLINDER:
                changed |= ImGui::SliderFloat2("R and h", &pPrimitiveData.x, 0.f, 8.f);
                if (changedScene)
                {
                    pPrimitiveData.xy = float2(0.6f,0.6);
                    mpCamera->setPosition(float3(2, 1.25, 1.5));
                    mpCamera->setTarget(float3(0, 0, 0));
                }
                break;
            case Scenes::TORUS:
                changed |= ImGui::SliderFloat2("R and r", &pPrimitiveData.x, 0.f, 8.f);
                if (changedScene)
                {
                    pPrimitiveData.xy = float2(0.9f, 0.3);
                    mpCamera->setPosition(float3(2, 1.25, 1.5));
                    mpCamera->setTarget(float3(0, 0, 0));
                }
                break;
            case Scenes::TEST:
                changed |= ImGui::SliderFloat3("Size", &pPrimitiveData.x, 0.f, 8.f);
                changed |= ImGui::SliderFloat3("TestPos", &pTestPos.x, 0.f, 8.f);
                if (changedScene)
                {
                    pPrimitiveData = float3(0.4f, 0.5f, 0.6f);
                    mpCamera->setPosition(float3(2, 1.25, 1.5));
                    mpCamera->setTarget(float3(0, 0, 0));
                }
                break;
            default:
                break;
            }
            if (static_cast<uint32_t>(Scenes::SPHERE) <= static_cast<uint32_t>(sceneID))
            {
                changed |= ImGui::SliderInt3("Repetition", &pRepeatNum.x, 0, 100);
                changed |= ImGui::SliderFloat3("Distance", &pRepeatDist.x, 0.f, 25.f);
                changed |= ImGui::Checkbox("Show ground plane", &pShowPlane);
            }
            if (changedScene && prevSceneID == Scenes::BLOBS && sceneID != Scenes::BLOBS)
            {
                primaryMaxIter = 256;
                primaryMaxDist = 500.f;
                shadowID = traceID == Tracers::SDF_TRACE ? Shadows::SDF_TRACE : Shadows::BDF_TRACE;
            }

            // TRACE

            settingsGroup.text("Trace:");
            bool traceChanged = false;
            ImGui::PushID("Trace:");
            if (sceneID == Scenes::BLOBS)
            {
                traceChanged |= settingsGroup.radioButtons(kTraceRBs, reinterpret_cast<uint32_t&>(traceID));
            }
            else
            {
                auto tracemethods = Gui::RadioButtonGroup(kTraceRBs.begin(), kTraceRBs.begin() + 2);
                traceChanged |= settingsGroup.radioButtons(tracemethods, reinterpret_cast<uint32_t&>(traceID));
            }
            ImGui::PopID();
            changed |= traceChanged;

            changed |= ImGui::SliderInt("PRIMARY_MAXITER", &primaryMaxIter, 1, 1024);
            changed |= ImGui::SliderFloat("PRIMARY_MAXDIST", &primaryMaxDist, 1.0f, 1024.0f);
            if (traceID == Tracers::SEGMENT_TRACE || traceID == Tracers::THEIR_SPHERE_TRACE)
            {
                changed |= ImGui::SliderFloat("S_MARCH_EPSILON", &sMarchEpsilon, 1e-15f, 1.f, "%.4f", 3.f);
            }
            if (traceID == Tracers::SEGMENT_TRACE)
            {
                changed |= ImGui::SliderFloat("S_KAPPA_FACTOR", &sKappaFactor, 1e-15f, 5.f);
            }

            // SHADOW
            if (changedColoring && colorID == Coloring::SHADOWSTEP)
            {
                shadowID = traceID == Tracers::SDF_TRACE ? Shadows::SDF_TRACE : Shadows::BDF_TRACE;
            }
            if (traceChanged && shadowID != Shadows::NO_SHADOW)
            {
                shadowID = traceID == Tracers::SDF_TRACE ? Shadows::SDF_TRACE : Shadows::BDF_TRACE;
            }
            if (sceneID == Scenes::BLOBS || colorID == Coloring::STEPSIZE)
            {
                shadowID = Shadows::NO_SHADOW;
            }
            else
            {
                settingsGroup.text("Shadow:");
                ImGui::PushID("Shadow:");
                changed |= settingsGroup.radioButtons(kShadowRBs, reinterpret_cast<uint32_t&>(shadowID));
                ImGui::PopID();
            }
            if (shadowID != Shadows::NO_SHADOW)
            {
                changed |= ImGui::SliderInt("SECONDARY_MAXITER", &secondaryMaxIter, 1, 1024);
                changed |= ImGui::SliderFloat("SECONDARY_MAXDIST", &secondaryMaxDist, 1.0f, 1024.0f);
                changed |= ImGui::SliderFloat("SECONDARY_MINDIST", &secondaryMinDist, 1e-15f, 1.f, "%.4f", 4.f);
                changed |= ImGui::SliderFloat("SECONDARY_EPSILON", &secondaryEpsilon, 1e-15f, 1.f, "%.4f", 4.f);
                changed |= ImGui::SliderFloat("SECONDARY_NOFFSET", &secondaryNOffset, 1e-15f, 1.f, "%.4f", 4.f);
            }
            // UPDATE SHADER
        }
        if (changed) {
            mpMainPass->addDefine("V_COLORING", std::to_string(static_cast<uint32_t>(colorID)));
            mpMainPass->addDefine("V_COLORING_FUNC", std::string("itershade") + kColorStepFunRBs[vColoringStepFunID].label);
            mpMainPass->addDefine("V_COLOR_A", std::string("vec3(")+std::to_string(vColorA.x)+','+std::to_string(vColorA.y)+','+std::to_string(vColorA.z)+')');
            mpMainPass->addDefine("V_COLOR_B", std::string("vec3(")+std::to_string(vColorB.x)+','+std::to_string(vColorB.y)+','+std::to_string(vColorB.z)+')');
            mpMainPass->addDefine("V_COLOR_C", std::string("vec3(")+std::to_string(vColorC.x)+','+std::to_string(vColorC.y)+','+std::to_string(vColorC.z)+')');
            mpMainPass->addDefine("V_COLOR_D", std::string("vec3(")+std::to_string(vColorD.x)+','+std::to_string(vColorD.y)+','+std::to_string(vColorD.z)+')');

            mpMainPass->addDefine("SCENE_SDF", std::string("sd") + kSceneRBs[reinterpret_cast<uint32_t&>(sceneID)].label);
            mpMainPass->addDefine("SCENE_BDF", std::string("bd") + kSceneRBs[reinterpret_cast<uint32_t&>(sceneID)].label);
            
            mpMainPass->addDefine(kTraceStr, kTraceRBs[reinterpret_cast<uint32_t&>(traceID)].label);
            mpMainPass->addDefine(kShadowStr, kShadowRBs[reinterpret_cast<uint32_t&>(shadowID)].label);

            mpMainPass->addDefine("PRIMARY_MAXITER", std::to_string(primaryMaxIter));
            mpMainPass->addDefine("PRIMARY_MAXDIST", std::to_string(primaryMaxDist));

            mpMainPass->addDefine("SECONDARY_MAXITER", std::to_string(secondaryMaxIter));
            mpMainPass->addDefine("SECONDARY_MAXDIST", std::to_string(secondaryMaxDist));
            mpMainPass->addDefine("SECONDARY_MINDIST", std::to_string(secondaryMinDist));
            mpMainPass->addDefine("SECONDARY_EPSILON", std::to_string(secondaryEpsilon));
            mpMainPass->addDefine("SECONDARY_NOFFSET", std::to_string(secondaryNOffset));

            mpMainPass->addDefine("S_THRESHOLD", std::to_string(sThreshold));
            mpMainPass->addDefine("S_BLOB_RADIUS", std::to_string(sBlobRadius));
            mpMainPass->addDefine("S_MARCH_EPSILON", std::to_string(sMarchEpsilon));
            mpMainPass->addDefine("S_KAPPA_FACTOR", std::to_string(sKappaFactor));

            mpMainPass->addDefine("P_REPEAT_X_NUM", std::to_string(pRepeatNum.x));
            mpMainPass->addDefine("P_REPEAT_Y_NUM", std::to_string(pRepeatNum.y));
            mpMainPass->addDefine("P_REPEAT_Z_NUM", std::to_string(pRepeatNum.z));
            mpMainPass->addDefine("P_REPEAT_DIST", std::string("vec3(")+std::to_string(pRepeatDist.x)+','+std::to_string(pRepeatDist.y)+','+std::to_string(pRepeatDist.z)+')');
            mpMainPass->addDefine("P_PRIMITIVE_DATA", std::string("vec3(") + std::to_string(pPrimitiveData.x) + ',' + std::to_string(pPrimitiveData.y) + ',' + std::to_string(pPrimitiveData.z) + ')');
            mpMainPass->addDefine("P_TEST_POS", std::string("vec3(") + std::to_string(pTestPos.x) + ',' + std::to_string(pTestPos.y) + ',' + std::to_string(pTestPos.z) + ')');
            mpMainPass->addDefine("P_PLANE_ON", std::to_string(static_cast<int>(pShowPlane)));

            mTestDataString = std::string("sc") +
                kColoringRBs[reinterpret_cast<uint32_t&>(colorID)].label + '_' +
                ((colorID == Coloring::STEPSIZE || colorID == Coloring::SHADOWSTEP) ? kColorStepFunRBs[vColoringStepFunID].label : "") + '_' +
                kSceneRBs[reinterpret_cast<uint32_t&>(sceneID)].label + "__" +
                kTraceRBs[reinterpret_cast<uint32_t&>(traceID)].label + "__" +
                "shadow-" +
                kShadowRBs[reinterpret_cast<uint32_t&>(shadowID)].label + "__" +
                "step-" + std::to_string(primaryMaxIter);
            prevSceneID = sceneID;
        }
        changed = false;

        ImGui::Text(mTestDataString.c_str());

        settingsGroup.release();
    }
}

void ShaderToy_BDF::onLoad(RenderContext* pRenderContext)
{
    // create camera
    mpCamera = Camera::create();
    mpCamera->setPosition(float3(0, 2, -4));
    mpCamera->setTarget(float3(0, 1, 0));
    mpCameraController = FirstPersonCameraController::create(mpCamera);
    mpCameraController->setCameraSpeed(5.f);
    mpCameraController->update();
    mpCamera->beginFrame();

    // Load shaders
    mpMainPass = FullScreenPass::create("Samples/ShaderToy_BDF/BDF.ps.slang");
}

void ShaderToy_BDF::onFrameRender(RenderContext* pRenderContext, const Fbo::SharedPtr& pTargetFbo)
{
    // camera
    mpCameraController->update();
    mpCamera->beginFrame();

    const float4 clearColor(0.38f, 0.52f, 0.10f, 1);
    pRenderContext->clearFbo(pTargetFbo.get(), clearColor, 1.0f, 0, FboAttachmentType::All);

    // iResolution
    float2 resolution = float2((float)pTargetFbo->getWidth(), (float)pTargetFbo->getHeight());
    mpMainPass["ToyCB"]["iResolution"] = resolution;
    mpMainPass["ToyCB"]["iTime"] = (float)gpFramework->getGlobalClock().getTime();

    static bool wasMouseButtonDownLastFrame = mpShadertoyMouse.z > 0;
    mpShadertoyMouse.w = abs(mpShadertoyMouse.w) * (!wasMouseButtonDownLastFrame && mpShadertoyMouse.z > 0 ? 1.f : -1.f );
    mpMainPass["ToyCB"]["iMouse"] = mpShadertoyMouse * float4(resolution, resolution);
    wasMouseButtonDownLastFrame = mpShadertoyMouse.z > 0;

    mpMainPass["Camera"]["camEye"] = mpCamera->getPosition();
    mpMainPass["Camera"]["camInvViewProj"] = mpCamera->getInvViewProjMatrix();

    // run final pass
    mpMainPass->execute(pRenderContext, pTargetFbo);
}

void ShaderToy_BDF::onShutdown()
{
}

bool ShaderToy_BDF::onKeyEvent(const KeyboardEvent& keyEvent)
{
    if (mpCameraController->onKeyEvent(keyEvent)) return true;

    if (keyEvent.type == KeyboardEvent::Type::KeyReleased) return false;

    switch (keyEvent.key)
    {
    case Input::Key::Escape:
        return true; // stop Falcor from exiting on pressing Escape
    case Input::Key::C:
        if (keyEvent.hasModifier(Input::Modifier::Ctrl)) {
            // copy model string to clipboard
            ImGui::SetClipboardText(mTestDataString.c_str());
            return true;
        }
        else {
            // create screen capture
            gpFramework->captureScreen(mTestDataString.c_str(), "captures");
            return true;
        }
        break;
    }

    return false;
}

bool ShaderToy_BDF::onMouseEvent(const MouseEvent& mouseEvent)
{
    mpCameraController->onMouseEvent(mouseEvent);
    static float mIsAnyButtonDown = -1.f; // float
    static float2 mMouseClickPos = float2(0);
    static float2 mMouseDragPos = float2(0);

    switch (mouseEvent.type)
    {
    case MouseEvent::Type::ButtonDown:
        if (mouseEvent.button == Input::MouseButton::Left || mouseEvent.button == Input::MouseButton::Right)
        {
            mMouseClickPos = mouseEvent.pos;
            mMouseDragPos = mouseEvent.pos;
            mIsAnyButtonDown = 1.f;
        }
        break;
    case MouseEvent::Type::ButtonUp:
        if (mouseEvent.button == Input::MouseButton::Left || mouseEvent.button == Input::MouseButton::Right)
        {
            mMouseDragPos = mouseEvent.pos;
            mIsAnyButtonDown = -1.f;
        }
        break;
    case MouseEvent::Type::Move:
        if (mIsAnyButtonDown == 1.f)
        {
            mMouseDragPos = mouseEvent.pos;
        }
        break;
    default:
        break;
    }
    mpShadertoyMouse.xy = mMouseDragPos;
    mpShadertoyMouse.zw = mMouseClickPos*float2(mIsAnyButtonDown,1.f);

    return false;
}

void ShaderToy_BDF::onHotReload(HotReloadFlags reloaded)
{
}

void ShaderToy_BDF::onResizeSwapChain(uint32_t width, uint32_t height)
{
    mAspectRatio = (float(width) / float(height));
    mpCamera->setAspectRatio(mAspectRatio);
}

int WINAPI WinMain(_In_ HINSTANCE hInstance, _In_opt_ HINSTANCE hPrevInstance, _In_ LPSTR lpCmdLine, _In_ int nShowCmd)
{
    ShaderToy_BDF::UniquePtr pRenderer = std::make_unique<ShaderToy_BDF>();
    SampleConfig config;
    config.windowDesc.width = 1280;
    config.windowDesc.height = 720;
    config.windowDesc.title = "BDF";
    config.windowDesc.resizableWindow = true;
    Sample::run(config, pRenderer);
    return 0;
}
