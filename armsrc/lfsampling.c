//-----------------------------------------------------------------------------
// This code is licensed to you under the terms of the GNU GPL, version 2 or,
// at your option, any later version. See the LICENSE.txt file for the text of
// the license.
//-----------------------------------------------------------------------------
// Miscellaneous routines for low frequency sampling.
//-----------------------------------------------------------------------------

#include "lfsampling.h"

#include "proxmark3_arm.h"
#include "BigBuf.h"
#include "fpgaloader.h"
#include "ticks.h"
#include "dbprint.h"
#include "util.h"
#include "lfdemod.h"
#include "string.h"  // memset
#include "appmain.h" // print stack

/*
Default LF config is set to:
    decimation = 1  (we keep 1 out of 1 samples)
    bits_per_sample = 8
    averaging = YES
    divisor = 95 (125kHz)
    trigger_threshold = 0
    samples_to_skip = 0
    verbose = YES
    */
static sample_config config = { 1, 8, 1, LF_DIVISOR_125, 0, 0, 1} ;

// Holds bit packed struct of samples.
static BitstreamOut data = {0, 0, 0};

// internal struct to keep track of samples gathered
static sampling_t samples = {0, 0, 0, 0};

void printConfig(void) {
    uint32_t d = config.divisor;
    DbpString(_CYAN_("LF Sampling config"));
    Dbprintf("  [q] divisor.............%d ( "_GREEN_("%d.%02d kHz")" )", d, 12000 / (d + 1), ((1200000 + (d + 1) / 2) / (d + 1)) - ((12000 / (d + 1)) * 100));
    Dbprintf("  [b] bits per sample.....%d", config.bits_per_sample);
    Dbprintf("  [d] decimation..........%d", config.decimation);
    Dbprintf("  [a] averaging...........%s", (config.averaging) ? "Yes" : "No");
    Dbprintf("  [t] trigger threshold...%d", config.trigger_threshold);
    Dbprintf("  [s] samples to skip.....%d ", config.samples_to_skip);

    DbpString(_CYAN_("LF Sampling Stack"));
    print_stack_usage();
}

void printSamples(void) {
    DbpString(_CYAN_("LF Sampling memory usage"));
//    Dbprintf("  decimation counter...%d", samples.dec_counter);
//    Dbprintf("  sum..................%u", samples.sum);
    Dbprintf("  counter.............." _YELLOW_("%u"), samples.counter);
    Dbprintf("  total saved.........." _YELLOW_("%u"), samples.total_saved);
    print_stack_usage();
}

/**
 * Called from the USB-handler to set the sampling configuration
 * The sampling config is used for standard reading and sniffing.
 *
 * Other functions may read samples and ignore the sampling config,
 * such as functions to read the UID from a prox tag or similar.
 *
 * Values set to '-1' implies no change
 * @brief setSamplingConfig
 * @param sc
 */
void setSamplingConfig(sample_config *sc) {

    // decimation (1-8) how many bits of adc sample value to save
    if (sc->decimation > 0 && sc->decimation < 8)
        config.decimation = sc->decimation;

    // bits per sample (1-8)
    if (sc->bits_per_sample > 0 && sc->bits_per_sample < 8)
        config.bits_per_sample = sc->bits_per_sample;

    //
    if (sc->averaging > -1)
        config.averaging = (sc->averaging > 0) ? 1 : 0;

    // Frequency divisor (19 - 255)
    if (sc->divisor > 18 && sc->divisor < 256)
        config.divisor = sc->divisor;

    // Start saving samples when adc value larger than trigger_threshold
    if (sc->trigger_threshold > -1)
        config.trigger_threshold = sc->trigger_threshold;

    // Skip n adc samples before saving
    if (sc->samples_to_skip > -1)
        config.samples_to_skip = sc->samples_to_skip;

    if (sc->verbose)
        printConfig();
}

sample_config *getSamplingConfig(void) {
    return &config;
}

/**
 * @brief Pushes bit onto the stream
 * @param stream
 * @param bit
 */
static void pushBit(BitstreamOut *stream, uint8_t bit) {
    int bytepos = stream->position >> 3; // divide by 8
    int bitpos = stream->position & 7;
    *(stream->buffer + bytepos) &= ~(1 << (7 - bitpos));
    *(stream->buffer + bytepos) |= (bit > 0) << (7 - bitpos);
    stream->position++;
    stream->numbits++;
}

void initSampleBuffer(uint32_t *sample_size) {
    initSampleBufferEx(sample_size, false);
}

void initSampleBufferEx(uint32_t *sample_size, bool use_malloc) {
    if (sample_size == NULL) {
        Dbprintf("initSampleBufferEx, param NULL");
        return;
    }
    BigBuf_free();

    // We can't erase the buffer now, it would drastically delay the acquisition
    if (use_malloc) {

        if (*sample_size == 0) {
            *sample_size = BigBuf_max_traceLen();
            data.buffer = BigBuf_get_addr();
        } else {
            *sample_size = MIN(*sample_size, BigBuf_max_traceLen());
            data.buffer = BigBuf_malloc(*sample_size);
        }

    } else {
        if (*sample_size == 0) {
            *sample_size = BigBuf_max_traceLen();
        } else {
            *sample_size = MIN(*sample_size, BigBuf_max_traceLen());
        }
        data.buffer = BigBuf_get_addr();
    }

    //
    samples.dec_counter = 0;
    samples.sum = 0;
    samples.counter = *sample_size;
    samples.total_saved = 0;
}

uint32_t getSampleCounter(void) {
    return samples.total_saved;
}

void logSampleSimple(uint8_t sample) {
    logSample(sample, config.decimation, config.bits_per_sample, config.averaging);
}

void logSample(uint8_t sample, uint8_t decimation, uint8_t bits_per_sample, bool avg) {

    if (!data.buffer) return;

    // keep track of total gather samples regardless how many was discarded.
    if (samples.counter-- == 0) return;

    if (bits_per_sample == 0) bits_per_sample = 1;
    if (bits_per_sample > 8) bits_per_sample = 8;
    if (decimation == 0) decimation = 1;

    if (avg) {
        samples.sum += sample;
    }

    // check decimation
    if (decimation > 1) {
        samples.dec_counter++;

        if (samples.dec_counter < decimation) return;

        samples.dec_counter = 0;
    }

    // averaging
    if (avg && decimation > 1) {
        sample = samples.sum / decimation;
        samples.sum = 0;
    }

    // store the sample
    samples.total_saved++;

    if (bits_per_sample == 8) {

        data.buffer[samples.total_saved - 1] = sample;

        // add number of bits.
        data.numbits = samples.total_saved << 3;

    } else {
        pushBit(&data, sample & 0x80);
        if (bits_per_sample > 1) pushBit(&data, sample & 0x40);
        if (bits_per_sample > 2) pushBit(&data, sample & 0x20);
        if (bits_per_sample > 3) pushBit(&data, sample & 0x10);
        if (bits_per_sample > 4) pushBit(&data, sample & 0x08);
        if (bits_per_sample > 5) pushBit(&data, sample & 0x04);
        if (bits_per_sample > 6) pushBit(&data, sample & 0x02);
    }
}

/**
* Setup the FPGA to listen for samples. This method downloads the FPGA bitstream
* if not already loaded, sets divisor and starts up the antenna.
* @param divisor : 1, 88> 255 or negative ==> 134.8 kHz
*                  0 or 95 ==> 125 kHz
*
**/
void LFSetupFPGAForADC(int divisor, bool reader_field) {
    FpgaDownloadAndGo(FPGA_BITSTREAM_LF);
    if ((divisor == 1) || (divisor < 0) || (divisor > 255))
        FpgaSendCommand(FPGA_CMD_SET_DIVISOR, LF_DIVISOR_134); //~134kHz
    else if (divisor == 0)
        FpgaSendCommand(FPGA_CMD_SET_DIVISOR, LF_DIVISOR_125); //125kHz
    else
        FpgaSendCommand(FPGA_CMD_SET_DIVISOR, divisor);

    FpgaWriteConfWord(FPGA_MAJOR_MODE_LF_READER | (reader_field ? FPGA_LF_ADC_READER_FIELD : 0));

    // Connect the A/D to the peak-detected low-frequency path.
    SetAdcMuxFor(GPIO_MUXSEL_LOPKD);

    // 50ms for the resonant antenna to settle.
    if (reader_field)
        SpinDelay(50);

    // Now set up the SSC to get the ADC samples that are now streaming at us.
    FpgaSetupSsc(FPGA_MAJOR_MODE_LF_READER);

    // start a 1.5ticks is 1us
    StartTicks();
}

/**
 * Does the sample acquisition. If threshold is specified, the actual sampling
 * is not commenced until the threshold has been reached.
 * This method implements decimation and quantization in order to
 * be able to provide longer sample traces.
 * Uses the following global settings:
 * @param decimation - how much should the signal be decimated. A decimation of N means we keep 1 in N samples, etc.
 * @param bits_per_sample - bits per sample. Max 8, min 1 bit per sample.
 * @param averaging If set to true, decimation will use averaging, so that if e.g. decimation is 3, the sample
 * value that will be used is the average value of the three samples.
 * @param trigger_threshold - a threshold. The sampling won't commence until this threshold has been reached. Set
 * to -1 to ignore threshold.
 * @param verbose - is true, dbprints the status,  else no outputs
 * @return the number of bits occupied by the samples.
 */
uint32_t DoAcquisition(uint8_t decimation, uint8_t bits_per_sample, bool avg, int16_t trigger_threshold,
                       bool verbose, uint32_t sample_size, uint32_t cancel_after, int32_t samples_to_skip) {

    initSampleBuffer(&sample_size);

    if (DBGLEVEL >= DBG_DEBUG) {
        Dbprintf("lf sampling - after init");
        printSamples();
    }

    uint32_t cancel_counter = 0;
    int16_t checked = 0;

    while (BUTTON_PRESS() == false) {

        // only every 1000th times, in order to save time when collecting samples.
        // interruptible only when logging not yet triggered
        if ((checked == 4000) && (trigger_threshold > 0)) {
            if (data_available()) {
                checked = -1;
                break;
            } else {
                checked = 0;
            }
        }
        ++checked;

        WDT_HIT();

        if (AT91C_BASE_SSC->SSC_SR & AT91C_SSC_TXRDY) {
            LED_D_ON();
        }

        if (AT91C_BASE_SSC->SSC_SR & AT91C_SSC_RXRDY) {
            volatile uint8_t sample = (uint8_t)AT91C_BASE_SSC->SSC_RHR;

            // Testpoint 8 (TP8) can be used to trigger oscilliscope
            LED_D_OFF();

            // threshold either high or low values 128 = center 0.  if trigger = 178
            if ((trigger_threshold > 0) && (sample < (trigger_threshold + 128)) && (sample > (128 - trigger_threshold))) {
                if (cancel_after > 0) {
                    cancel_counter++;
                    if (cancel_after == cancel_counter)
                        break;
                }
                continue;
            }

            trigger_threshold = 0;

            if (samples_to_skip > 0) {
                samples_to_skip--;
                continue;
            }

            logSample(sample, decimation, bits_per_sample, avg);

            if (samples.total_saved >= sample_size) break;
        }
    }

    if (checked == -1 && verbose) {
        Dbprintf("lf sampling aborted");
    }

    if (verbose) {
        Dbprintf("Done, saved " _YELLOW_("%d")" out of " _YELLOW_("%d")" seen samples at " _YELLOW_("%d")" bits/sample", samples.total_saved, samples.counter, bits_per_sample);
    }

    // Ensure that DC offset removal and noise check is performed for any device-side processing
    removeSignalOffset(data.buffer, samples.total_saved);
    computeSignalProperties(data.buffer, samples.total_saved);

    return data.numbits;
}
/**
 * @brief Does sample acquisition, ignoring the config values set in the sample_config.
 * This method is typically used by tag-specific readers who just wants to read the samples
 * the normal way
 * @param trigger_threshold
 * @param verbose
 * @return number of bits sampled
 */
uint32_t DoAcquisition_default(int trigger_threshold, bool verbose) {
    return DoAcquisition(1, 8, 0, trigger_threshold, verbose, 0, 0, 0);
}
uint32_t DoAcquisition_config(bool verbose, uint32_t sample_size) {
    return DoAcquisition(config.decimation
                         , config.bits_per_sample
                         , config.averaging
                         , config.trigger_threshold
                         , verbose
                         , sample_size
                         , 0
                         , config.samples_to_skip);
}

uint32_t DoPartialAcquisition(int trigger_threshold, bool verbose, uint32_t sample_size, uint32_t cancel_after) {
    return DoAcquisition(1, 8, 0, trigger_threshold, verbose, sample_size, cancel_after, 0);
}

static uint32_t ReadLF(bool reader_field, bool verbose, uint32_t sample_size) {
    if (verbose)
        printConfig();

    LFSetupFPGAForADC(config.divisor, reader_field);
    uint32_t ret = DoAcquisition_config(verbose, sample_size);
    FpgaWriteConfWord(FPGA_MAJOR_MODE_OFF);
    return ret;
}

/**
* Initializes the FPGA for reader-mode (field on), and acquires the samples.
* @return number of bits sampled
**/
uint32_t SampleLF(bool verbose, uint32_t sample_size) {
    BigBuf_Clear_ext(false);
    return ReadLF(true, verbose, sample_size);
}
/**
* Initializes the FPGA for sniffer-mode (field off), and acquires the samples.
* @return number of bits sampled
**/
uint32_t SniffLF(void) {
    BigBuf_Clear_ext(false);
    return ReadLF(false, true, 0);
}

/**
* acquisition of T55x7 LF signal. Similar to other LF, but adjusted with @marshmellows thresholds
* the data is collected in BigBuf.
**/
void doT55x7Acquisition(size_t sample_size) {

#define T55xx_READ_UPPER_THRESHOLD 128+60  // 60 grph
#define T55xx_READ_LOWER_THRESHOLD 128-60  // -60 grph
#define T55xx_READ_TOL   5

    uint8_t *dest = BigBuf_get_addr();
    uint16_t bufsize = BigBuf_max_traceLen();

    if (bufsize > sample_size)
        bufsize = sample_size;

    uint8_t lastSample = 0;
    uint16_t i = 0, skipCnt = 0;
    bool startFound = false;
    bool highFound = false;
    bool lowFound = false;

    uint16_t checker = 0;

    if (DBGLEVEL >= DBG_DEBUG) {
        Dbprintf("doT55x7Acquisition - after init");
        print_stack_usage();
    }

    while (skipCnt < 1000 && (i < bufsize)) {

        if (BUTTON_PRESS())
            break;

        if (checker == 4000) {
            if (data_available())
                break;
            else
                checker = 0;
        } else {
            ++checker;
        }

        WDT_HIT();

        if (AT91C_BASE_SSC->SSC_SR & AT91C_SSC_TXRDY) {
            LED_D_ON();
        }

        if (AT91C_BASE_SSC->SSC_SR & AT91C_SSC_RXRDY) {
            volatile uint8_t sample = (uint8_t)AT91C_BASE_SSC->SSC_RHR;
            LED_D_OFF();

            // skip until the first high sample above threshold
            if (!startFound && sample > T55xx_READ_UPPER_THRESHOLD) {
                highFound = true;
            } else if (!highFound) {
                skipCnt++;
                continue;
            }
            // skip until the first low sample below threshold
            if (!startFound && sample < T55xx_READ_LOWER_THRESHOLD) {
                lastSample = sample;
                lowFound = true;
            } else if (!lowFound) {
                skipCnt++;
                continue;
            }

            // skip until first high samples begin to change
            if (startFound || sample > T55xx_READ_LOWER_THRESHOLD + T55xx_READ_TOL) {
                // if just found start - recover last sample
                if (!startFound) {
                    dest[i++] = lastSample;
                    startFound = true;
                }
                // collect samples
                dest[i++] = sample;
            }
        }
    }
}
/**
* acquisition of Cotag LF signal. Similart to other LF,  since the Cotag has such long datarate RF/384
* and is Manchester?,  we directly gather the manchester data into bigbuff
**/

#define COTAG_T1 384
#define COTAG_T2 (COTAG_T1>>1)
#define COTAG_ONE_THRESHOLD 128+5
#define COTAG_ZERO_THRESHOLD 128-5
#ifndef COTAG_BITS
#define COTAG_BITS 264
#endif
void doCotagAcquisition() {

    uint8_t *dest = BigBuf_get_addr();
    uint16_t bufsize = BigBuf_max_traceLen();

    dest[0] = 0;
    uint8_t firsthigh = 0, firstlow = 0;
    uint16_t i = 0, noise_counter = 0;

    if (DBGLEVEL >= DBG_DEBUG) {
        Dbprintf("doCotagAcquisition - after init");
        print_stack_usage();
    }

    while ((i < bufsize) && (noise_counter < (COTAG_T1 << 1))) {

        if (BUTTON_PRESS())
            break;

        WDT_HIT();

        if (AT91C_BASE_SSC->SSC_SR & AT91C_SSC_RXRDY) {
            volatile uint8_t sample = (uint8_t)AT91C_BASE_SSC->SSC_RHR;

            // find first peak
            if (!firsthigh) {
                if (sample < COTAG_ONE_THRESHOLD) {
                    noise_counter++;
                    continue;
                }
                noise_counter = 0;
                firsthigh = 1;
            }
            if (!firstlow) {
                if (sample > COTAG_ZERO_THRESHOLD) {
                    noise_counter++;
                    continue;
                }
                noise_counter = 0;
                firstlow = 1;
            }

            ++i;

            if (sample > COTAG_ONE_THRESHOLD)
                dest[i] = 255;
            else if (sample < COTAG_ZERO_THRESHOLD)
                dest[i] = 0;
            else
                dest[i] = dest[i - 1];
        }
    }

    Dbprintf("doCotagAcquisition - %u high %u == 1   low %u == 1", i, firsthigh, firstlow);

    // Ensure that DC offset removal and noise check is performed for any device-side processing
    removeSignalOffset(dest, bufsize);
    printSamples();
    computeSignalProperties(dest, bufsize);
    printSamples();
}

uint32_t doCotagAcquisitionManchester(void) {

    uint8_t *dest = BigBuf_get_addr();
    uint16_t bufsize = MIN(COTAG_BITS, BigBuf_max_traceLen());

    dest[0] = 0;
    uint8_t firsthigh = 0, firstlow = 0;
    uint8_t curr = 0, prev = 0;
    uint16_t sample_counter = 0, period = 0;
    uint16_t noise_counter = 0;

    if (DBGLEVEL >= DBG_DEBUG) {
        Dbprintf("doCotagAcquisitionManchester - after init");
        print_stack_usage();
    }

    while ((sample_counter < bufsize) && (noise_counter < (COTAG_T1 << 1))) {

        if (BUTTON_PRESS())
            break;

        WDT_HIT();

        if (AT91C_BASE_SSC->SSC_SR & AT91C_SSC_TXRDY) {
            LED_D_ON();
        }

        if (AT91C_BASE_SSC->SSC_SR & AT91C_SSC_RXRDY) {
            volatile uint8_t sample = (uint8_t)AT91C_BASE_SSC->SSC_RHR;

            // find first peak
            if (!firsthigh) {
                if (sample < COTAG_ONE_THRESHOLD) {
                    noise_counter++;
                    continue;
                }
                noise_counter = 0;
                firsthigh = 1;
            }

            if (!firstlow) {
                if (sample > COTAG_ZERO_THRESHOLD) {
                    noise_counter++;
                    continue;
                }
                noise_counter = 0;
                firstlow = 1;
            }

            // set sample 255, 0,  or previous
            if (sample > COTAG_ONE_THRESHOLD) {
                prev = curr;
                curr = 1;
            } else if (sample < COTAG_ZERO_THRESHOLD) {
                prev = curr;
                curr = 0;
            } else {
                curr = prev;
            }

            // full T1 periods,
            if (period > 0) {
                --period;
                continue;
            }

            dest[sample_counter] = curr;
            ++sample_counter;
            period = COTAG_T1;
        }
    }
    return sample_counter;
}
