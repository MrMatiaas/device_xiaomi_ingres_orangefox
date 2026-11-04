/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Minimal IVibrator for POCO F4 GT (ingres) recovery: on/off only, via the
 * awinic_haptic i2c driver's sysfs node (duration in ms, then activate=1).
 */

#include <aidl/android/hardware/vibrator/BnVibrator.h>
#include <android-base/file.h>
#include <android-base/logging.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>

#include <dirent.h>
#include <string>
#include <thread>

using aidl::android::hardware::vibrator::Braking;
using aidl::android::hardware::vibrator::BnVibrator;
using aidl::android::hardware::vibrator::CompositeEffect;
using aidl::android::hardware::vibrator::CompositePrimitive;
using aidl::android::hardware::vibrator::Effect;
using aidl::android::hardware::vibrator::EffectStrength;
using aidl::android::hardware::vibrator::IVibrator;
using aidl::android::hardware::vibrator::IVibratorCallback;
using aidl::android::hardware::vibrator::PrimitivePwle;

namespace {

constexpr char kDriverDir[] = "/sys/bus/i2c/drivers/awinic_haptic";

// Find "<bus>-005a"-style device dir under the driver (bus number may vary).
std::string findHapticNode() {
    DIR* d = opendir(kDriverDir);
    if (!d) return "";
    std::string found;
    while (struct dirent* de = readdir(d)) {
        std::string dir = std::string(kDriverDir) + "/" + de->d_name;
        if (de->d_name[0] != '.' && access((dir + "/activate").c_str(), W_OK) == 0) {
            found = dir;
            break;
        }
    }
    closedir(d);
    return found;
}

ndk::ScopedAStatus unsupported() {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

class Vibrator : public BnVibrator {
  public:
    explicit Vibrator(std::string node) : mNode(std::move(node)) {}

    ndk::ScopedAStatus getCapabilities(int32_t* ret) override {
        *ret = IVibrator::CAP_ON_CALLBACK;
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus off() override {
        write("activate", "0");
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus on(int32_t timeoutMs,
                          const std::shared_ptr<IVibratorCallback>& callback) override {
        if (timeoutMs <= 0) return off();
        if (!write("duration", std::to_string(timeoutMs)) || !write("activate", "1"))
            return ndk::ScopedAStatus::fromExceptionCode(EX_SERVICE_SPECIFIC);
        if (callback != nullptr) {
            std::thread([timeoutMs, callback] {
                usleep(timeoutMs * 1000);
                callback->onComplete();
            }).detach();
        }
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus perform(Effect, EffectStrength, const std::shared_ptr<IVibratorCallback>&,
                               int32_t*) override { return unsupported(); }
    ndk::ScopedAStatus getSupportedEffects(std::vector<Effect>* ret) override {
        ret->clear();
        return ndk::ScopedAStatus::ok();
    }
    ndk::ScopedAStatus setAmplitude(float) override { return unsupported(); }
    ndk::ScopedAStatus setExternalControl(bool) override { return unsupported(); }
    ndk::ScopedAStatus getCompositionDelayMax(int32_t*) override { return unsupported(); }
    ndk::ScopedAStatus getCompositionSizeMax(int32_t*) override { return unsupported(); }
    ndk::ScopedAStatus getSupportedPrimitives(std::vector<CompositePrimitive>* ret) override {
        ret->clear();
        return ndk::ScopedAStatus::ok();
    }
    ndk::ScopedAStatus getPrimitiveDuration(CompositePrimitive, int32_t*) override {
        return unsupported();
    }
    ndk::ScopedAStatus compose(const std::vector<CompositeEffect>&,
                               const std::shared_ptr<IVibratorCallback>&) override {
        return unsupported();
    }
    ndk::ScopedAStatus getSupportedAlwaysOnEffects(std::vector<Effect>* ret) override {
        ret->clear();
        return ndk::ScopedAStatus::ok();
    }
    ndk::ScopedAStatus alwaysOnEnable(int32_t, Effect, EffectStrength) override {
        return unsupported();
    }
    ndk::ScopedAStatus alwaysOnDisable(int32_t) override { return unsupported(); }
    ndk::ScopedAStatus getResonantFrequency(float*) override { return unsupported(); }
    ndk::ScopedAStatus getQFactor(float*) override { return unsupported(); }
    ndk::ScopedAStatus getFrequencyResolution(float*) override { return unsupported(); }
    ndk::ScopedAStatus getFrequencyMinimum(float*) override { return unsupported(); }
    ndk::ScopedAStatus getBandwidthAmplitudeMap(std::vector<float>*) override {
        return unsupported();
    }
    ndk::ScopedAStatus getPwlePrimitiveDurationMax(int32_t*) override { return unsupported(); }
    ndk::ScopedAStatus getPwleCompositionSizeMax(int32_t*) override { return unsupported(); }
    ndk::ScopedAStatus getSupportedBraking(std::vector<Braking>*) override {
        return unsupported();
    }
    ndk::ScopedAStatus composePwle(const std::vector<PrimitivePwle>&,
                                   const std::shared_ptr<IVibratorCallback>&) override {
        return unsupported();
    }

  private:
    bool write(const char* file, const std::string& value) {
        std::string path = mNode + "/" + file;
        if (!android::base::WriteStringToFile(value, path)) {
            PLOG(ERROR) << "write " << path;
            return false;
        }
        return true;
    }

    const std::string mNode;
};

}  // namespace

int main() {
    std::string node = findHapticNode();
    if (node.empty()) {
        LOG(ERROR) << "no awinic_haptic device under " << kDriverDir << ", exiting";
        return 1;  // service is oneshot in init.recovery.qcom.rc, so no respawn loop
    }
    LOG(INFO) << "using haptic node " << node;

    ABinderProcess_setThreadPoolMaxThreadCount(0);
    auto vib = ndk::SharedRefBase::make<Vibrator>(node);
    // Instance must match TW_SUPPORT_INPUT_AIDL_HAPTICS_FQNAME and the VINTF fragment.
    const std::string instance = std::string(Vibrator::descriptor) + "/vibratorfeature";
    if (AServiceManager_addService(vib->asBinder().get(), instance.c_str()) != STATUS_OK) {
        LOG(ERROR) << "failed to register " << instance;
        return 1;
    }
    ABinderProcess_joinThreadPool();
    return 1;
}
