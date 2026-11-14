import { Body, Controller, Delete, Get, Post, Put, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Endpoint, HistoryBuilder } from 'src/decorators.js';
import type { AuthDto } from 'src/dtos/auth.dto.js';
import { ApiTag, Permission } from 'src/enum.js';
import { Auth, Authenticated } from 'src/middleware/auth.guard.js';
import {
  AiDedupClearResultDto,
  AiDedupCredentialDto,
  AiDedupCredentialStatusDto,
  AiDedupDeleteScoresDto,
  AiDedupEvaluateDto,
  AiDedupEvaluateResponseDto,
  AiDedupPromptDto,
  AiDedupPurgeResultDto,
  AiDedupTestConnectionDto,
  AiDedupTestResultDto,
  AiDedupUsageDto,
  AiDedupUsageQueryDto,
} from 'src/ai-dedup/dto.js';
import { AiDedupService } from 'src/ai-dedup/ai-dedup.service.js';

const history = () => new HistoryBuilder().added('v3.4.0-ai-dedup').alpha('v3.4.0-ai-dedup');

/**
Eight independent endpoints for the AI dedup feature. No `{code,data,message}` wrapper:
responses follow the existing Immich convention (plain objects / DTOs).
Deletion still goes exclusively through the existing POST /api/duplicates/resolve.
*/
@ApiTags(ApiTag.AiDedup)
@Controller('ai-dedup')
export class AiDedupController {
  constructor(private service: AiDedupService) {}

  /** E1: on-demand evaluation / cache lookup; per-group degradation, never a whole-request error. */
  @Post('evaluate')
  @Authenticated({ permission: Permission.DuplicateRead })
  @Endpoint({
    summary: 'Evaluate duplicate groups with AI',
    description:
      'Return AI quality scores and a recommended keep set per duplicate group. Each group degrades independently to the existing heuristic recommendation.',
    history: history(),
  })
  evaluateAiDedup(@Auth() auth: AuthDto, @Body() dto: AiDedupEvaluateDto): Promise<AiDedupEvaluateResponseDto> {
    return this.service.evaluate(auth, dto);
  }

  /** E2: prompt/version/privacy state for the duplicates page; contains no credentials. */
  @Get('prompt')
  @Authenticated({ permission: Permission.DuplicateRead })
  @Endpoint({
    summary: 'Get the AI dedup prompt and state',
    description:
      'Return the fixed prompt template, strategy summary, enabled flag and trash.enabled so the confirmation dialog can warn about permanent deletion.',
    history: history(),
  })
  getAiDedupPrompt(): Promise<AiDedupPromptDto> {
    return this.service.getPrompt();
  }

  /** E3: masked credential status (admin only). */
  @Get('credential')
  @Authenticated({ admin: true })
  @Endpoint({
    summary: 'Get AI dedup credential status',
    description: 'Return whether a credential is configured and its masked form; never the plaintext.',
    history: history(),
  })
  getAiDedupCredential(): Promise<AiDedupCredentialStatusDto> {
    return this.service.getCredentialStatus();
  }

  /** E4: AES-256-GCM encrypted credential write into system_metadata. */
  @Put('credential')
  @Authenticated({ admin: true })
  @Endpoint({
    summary: 'Set the AI dedup credential',
    description: 'Encrypt and store the model apiKey. The plaintext is never returned or logged.',
    history: history(),
  })
  putAiDedupCredential(@Body() dto: AiDedupCredentialDto): Promise<AiDedupCredentialStatusDto> {
    return this.service.putCredential(dto);
  }

  /** E5: clear the credential and its in-memory cache. */
  @Delete('credential')
  @Authenticated({ admin: true })
  @Endpoint({
    summary: 'Clear the AI dedup credential',
    description: 'Delete the stored credential and reset the in-memory plaintext cache.',
    history: history(),
  })
  deleteAiDedupCredential(): Promise<AiDedupClearResultDto> {
    return this.service.clearCredential();
  }

  /** E6: one-click data clearing (scores + optional usage). */
  @Delete('scores')
  @Authenticated({ admin: true })
  @Endpoint({
    summary: 'Clear AI dedup scores',
    description: 'Delete cached scores and (optionally) usage counters, scoped by ownerId when provided.',
    history: history(),
  })
  deleteAiDedupScores(@Body() dto: AiDedupDeleteScoresDto): Promise<AiDedupPurgeResultDto> {
    return this.service.purgeScores(dto);
  }

  /** E7: connectivity / vision capability probe; uses a built-in 1x1 image only. */
  @Post('test-connection')
  @Authenticated({ admin: true })
  @Endpoint({
    summary: 'Test the AI dedup model connection',
    description: 'Probe connectivity, authentication and image input support without sending any real user photo.',
    history: history(),
  })
  testAiDedupConnection(@Body() dto: AiDedupTestConnectionDto): Promise<AiDedupTestResultDto> {
    return this.service.testConnection(dto);
  }

  /** E8: usage and estimated cost readout. */
  @Get('usage')
  @Authenticated({ admin: true })
  @Endpoint({
    summary: 'Get AI dedup usage',
    description: 'Return today/month usage and estimated cost, optionally filtered by owner and month.',
    history: history(),
  })
  getAiDedupUsage(@Query() query: AiDedupUsageQueryDto): Promise<AiDedupUsageDto> {
    return this.service.getUsage(query);
  }
}
