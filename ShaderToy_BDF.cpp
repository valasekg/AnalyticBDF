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
    Gui::RadioButtonGroup kSceneRBs = { {0,"Blobs", false}, {1,"Primitives", true} };
    static const std::string kSceneDFs_sdf[] = { "sdf", "sdf2" };
    static const std::string kSceneDFs_bdf[] = { "bdf", "bdf2" };

    Gui::RadioButtonGroup kTraceRBs = { {0,"sdf_trace", false}, {1,"bdf_trace", true} };
    Gui::RadioButtonGroup kShadowRBs = { {0,"sdf_trace", false}, {1,"bdf_trace", true}, {2,"no_shadow",true} };
}

void ShaderToy_BDF::onGuiRender(Gui* pGui)
{
    Gui::Window w(pGui, "Falcor", { 350, 500 });
    gpFramework->renderGlobalUI(pGui);
    auto camearGroup = Gui::Group(pGui, "Camera Controls", false);
    if (camearGroup.open())
    {
        if (camearGroup.button("Reset camera")) {
            mpCamera->setPosition(float3(0, 2, -4));
            mpCamera->setTarget(float3(0, 1, 0));
        }
        mpCamera->renderUI(w);

        camearGroup.release();
    }
    auto settingsGroup = Gui::Group(pGui, "Settings", true);
    if (settingsGroup.open())
    {
        bool changed = false;

        static uint32_t sceneID = 0;
        settingsGroup.text(kSceneStr);
        ImGui::PushID(kSceneStr);
        changed |= settingsGroup.radioButtons(kSceneRBs, sceneID);
        ImGui::PopID();

        static uint32_t traceID = 0;
        settingsGroup.text(kTraceStr);
        ImGui::PushID(kTraceStr);
        changed |= settingsGroup.radioButtons(kTraceRBs, traceID);
        ImGui::PopID();

        static uint32_t shadowID = 2;
        settingsGroup.text(kShadowStr);
        ImGui::PushID(kShadowStr);
        changed |= settingsGroup.radioButtons(kShadowRBs, shadowID);
        ImGui::PopID();

        if (changed) {
            mpMainPass->addDefine("SCENE_SDF", kSceneDFs_sdf[ sceneID ]);
            mpMainPass->addDefine("SCENE_BDF", kSceneDFs_bdf[ sceneID ]);
            
            mpMainPass->addDefine(kTraceStr, kTraceRBs[traceID].label);
            mpMainPass->addDefine(kShadowStr, kShadowRBs[shadowID].label);
        }

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
    float width = (float)pTargetFbo->getWidth();
    float height = (float)pTargetFbo->getHeight();
    mpMainPass["ToyCB"]["iResolution"] = float2(width, height);
    mpMainPass["ToyCB"]["iGlobalTime"] = (float)gpFramework->getGlobalClock().getTime();
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

    return false;
}

bool ShaderToy_BDF::onMouseEvent(const MouseEvent& mouseEvent)
{
    mpCameraController->onMouseEvent(mouseEvent);

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
