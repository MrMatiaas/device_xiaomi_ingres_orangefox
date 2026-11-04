/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Minimal IVibrator for POCO F4 GT (ingres) recovery: on/off only, via the
 * awinic aw86927 haptic driver's sysfs node (duration in ms, then activate=1).
 *
 * The i2c driver name depends on the kernel the recovery borrows from the
 * active boot slot: "awinic_haptic" on stock HyperOS, "aw8697_haptic" on
 * e.g. EvolutionX. So scan for any haptic-looking i2c driver, falling back to
 * the classic LED-class vibrator node.
 *
 * The service is ALWAYS registered, even with no motor found: recovery's
 * vibrate() blocks ~5s per call in AServiceManager_getService() when the
 * instance is missing, which made every tap take 5+ seconds.
 */

#include <aidl/android/hardware/vibrator/BnVibrator.h>
#include <android-base/file.h>
#include <android-base/logging.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>

#include <dirent.h>
#include <mutex>
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

constexpr char kI2cDrivers[] = "/sys/bus/i2c/drivers";
constexpr char kLedVibrator[] = "/sys/class/leds/vibrator";

bool isVibratorNode(const std::string& dir) {
    return access((dir + "/activate").c_str(), W_OK) == 0 &&
           access((dir + "/duration").c_str(), W_OK) == 0;
}

// Return the first "<bus>-<addr>" device dir under `driverDir` that exposes
// activate + duration (bus number varies between kernels).
std::string findInDriver(const std::string& driverDir) {
    DIR* d = opendir(driverDir.c_str());
    if (!d) return "";
    std::string found;
    while (struct dirent* de = readdir(d)) {
        if (de->d_name[0] == '.') continue;
        std::string dir = driverDir + "/" + de->d_name;
        if (isVibratorNode(dir)) {
            found = dir;
            break;
        }
    }
    closedir(d);
    return found;
}

std::string findHapticNode() {
    // Known names first, then anything that looks like a haptic driver.
    for (const char* name : {"awinic_haptic", "aw8697_haptic", "aw86927_haptic"}) {
        std::string n = findInDriver(std::string(kI2cDrivers) + "/" + name);
        if (!n.empty()) return n;
    }
    if (DIR* d = opendir(kI2cDrivers)) {
        std::string found;
        while (struct dirent* de = readdir(d)) {
            std::string name = de->d_name;
            if (name.find("haptic") == std::string::npos && name.rfind("aw86", 0) != 0) continue;
            found = findInDriver(std::string(kI2cDrivers) + "/" + name);
            if (!found.empty()) break;
        }
        closedir(d);
        if (!found.empty()) return found;
    }
    if (isVibratorNode(kLedVibrator)) return kLedVibrator;
    return "";
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
        if (node().empty()) return ndk::ScopedAStatus::ok();
        write("activate", "0");
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus on(int32_t timeoutMs,
                          const std::shared_ptr<IVibratorCallback>& callback) override {
        if (timeoutMs <= 0) return off();
        if (node().empty()) return ndk::ScopedAStatus::ok();  // no motor: silent no-op
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
    // Cached node; re-scanned lazily if none was found yet (driver may probe late).
    std::string node() {
        std::lock_guard<std::mutex> lock(mLock);
        if (mNode.empty()) {
            mNode = findHapticNode();
            if (!mNode.empty()) LOG(INFO) << "using haptic node " << mNode;
        }
        return mNode;
    }

    bool write(const char* file, const std::string& value) {
        std::string path = node() + "/" + file;
        if (!android::base::WriteStringToFile(value, path)) {
            PLOG(ERROR) << "write " << path;
            return false;
        }
        return true;
    }

    std::mutex mLock;
    std::string mNode;
};

}  // namespace

int main() {
    std::string node = findHapticNode();
    if (node.empty())
        LOG(WARNING) << "no haptic sysfs node found yet; registering anyway (vibration is a "
                        "no-op until one appears) so recovery never blocks waiting for us";
    else
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
