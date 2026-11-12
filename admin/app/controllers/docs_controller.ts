import { DocsService } from '#services/docs_service'
import { inject } from '@adonisjs/core'
import type { HttpContext } from '@adonisjs/core/http'

@inject()
export default class DocsController {
    constructor(
        private docsService: DocsService
    ) { }

    async list({ }: HttpContext) {
        return await this.docsService.getDocs();
    }

    async show({ params, inertia, response }: HttpContext) {
        // A slug with a file extension (e.g. dashboard.webp) can never be a
        // doc page: it is a static asset whose URL collided with this
        // catch-all. Answer 404, not 500, so a missing image never looks
        // like a server error.
        if (/\.[a-z0-9]+$/i.test(params.slug)) {
          return response.notFound({ error: 'Document not found' })
        }
        const content = await this.docsService.parseFile(params.slug);
        return inertia.render('docs/show', {
            content,
        });
    }
}